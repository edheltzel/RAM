import Foundation
import AppKit

enum Grouping {
    static let rowCap = 10

    static func rows(
        view: ListView,
        processes: [Proc],
        filter: String,
        expanded: Set<String>,
        sortDescending: Bool
    ) -> [ListRow] {
        switch view {
        case .process:
            return cap(filterRows(sortedRows(processes.map(processRow), descending: sortDescending), filter: filter))
        case .nested:
            return nestedVisible(appRows(processes, nested: true, expanded: expanded, sortDescending: sortDescending), filter: filter)
        }
    }

    private static func memoryBefore(_ a: UInt64, _ b: UInt64, descending: Bool) -> Bool {
        descending ? a > b : a < b
    }

    private static func sortedRows(_ rows: [ListRow], descending: Bool) -> [ListRow] {
        rows.sorted { memoryBefore($0.bytes, $1.bytes, descending: descending) }
    }

    private static func sortedProcs(_ procs: [Proc], descending: Bool) -> [Proc] {
        procs.sorted { memoryBefore($0.bytes, $1.bytes, descending: descending) }
    }

    private static func processRow(_ proc: Proc) -> ListRow {
        ListRow(
            id: "p:\(proc.pid)",
            title: proc.displayName,
            bytes: proc.bytes,
            kind: .process(pid: proc.pid),
            depth: 0,
            expandable: false,
            expanded: false,
            children: [proc]
        )
    }

    /// GUI apps collapse by bundle: two Brave windows = one Brave. A process only joins an
    /// app row if its executable lives inside that app's bundle. Terminal.app is summed that
    /// way; shells and coding agents hosted *in* a terminal stay separate process rows.
    private static func appRows(_ processes: [Proc], nested: Bool, expanded: Set<String>, sortDescending: Bool) -> [ListRow] {
        let gui = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var claimed = Set<Int32>()
        var rows: [ListRow] = []

        for app in gui {
            guard let bundleURL = app.bundleURL else { continue }
            let root = bundleURL.standardizedFileURL.path
            let members = processes.filter { proc in
                !proc.path.isEmpty && proc.path.hasPrefix(root + "/")
            }
            guard !members.isEmpty else { continue }
            members.forEach { claimed.insert($0.pid) }
            let id = "app:\(app.bundleIdentifier ?? app.localizedName ?? "\(app.processIdentifier)")"
            let title = app.localizedName ?? URL(fileURLWithPath: root).deletingPathExtension().lastPathComponent
            rows.append(
                ListRow(
                    id: id,
                    title: title,
                    bytes: members.reduce(0) { $0 + $1.bytes },
                    kind: .group,
                    depth: 0,
                    expandable: nested,
                    expanded: nested && expanded.contains(id),
                    children: sortedProcs(members, descending: sortDescending)
                )
            )
        }

        for proc in processes where !claimed.contains(proc.pid) {
            rows.append(processRow(proc))
        }
        return sortedRows(rows, descending: sortDescending)
    }

    private static func nestedVisible(_ parents: [ListRow], filter: String) -> [ListRow] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [ListRow] = []
        var parentsShown = 0
        for parent in parents {
            if parentsShown >= rowCap { break }
            let childHits = parent.children.filter { matches($0.displayName, pid: $0.pid, filter: needle) }
            let parentHit = needle.isEmpty || matches(parent.title, pid: nil, filter: needle) || !childHits.isEmpty
            guard parentHit else { continue }
            out.append(parent)
            parentsShown += 1
            if parent.expandable && parent.expanded {
                let kids = needle.isEmpty ? parent.children : childHits
                for child in kids {
                    out.append(
                        ListRow(
                            id: "\(parent.id)/p:\(child.pid)",
                            title: child.displayName,
                            bytes: child.bytes,
                            kind: .process(pid: child.pid),
                            depth: 1,
                            expandable: false,
                            expanded: false,
                            children: [child]
                        )
                    )
                }
            }
        }
        return out
    }

    private static func filterRows(_ rows: [ListRow], filter: String) -> [ListRow] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return rows }
        return rows.filter { row in
            if matches(row.title, pid: nil, filter: needle) { return true }
            return row.children.contains { matches($0.displayName, pid: $0.pid, filter: needle) }
        }
    }

    private static func matches(_ name: String, pid: Int32?, filter: String) -> Bool {
        if filter.isEmpty { return true }
        if name.lowercased().contains(filter) { return true }
        if let pid, String(pid).contains(filter) { return true }
        return false
    }

    private static func cap(_ rows: [ListRow]) -> [ListRow] {
        Array(rows.prefix(rowCap))
    }
}
