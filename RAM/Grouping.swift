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

    /// GUI apps collapse by bundle: two Brave windows = one Brave. A process joins an
    /// app row when its executable lives inside that bundle, or when its path is empty
    /// and its bundle id matches. One PID is summed once. Terminal.app is summed that
    /// way; shells and coding agents hosted in a terminal stay separate process rows.
    private static func appRows(_ processes: [Proc], nested: Bool, expanded: Set<String>, sortDescending: Bool) -> [ListRow] {
        let gui = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        var claimed = Set<Int32>()
        var rows: [ListRow] = []
        // One group per bundle identity — multiple NSRunningApplication instances of the
        // same app must not each emit an identical parent/children set.
        var seenIdentity = Set<String>()

        for app in gui {
            guard let bundleURL = app.bundleURL else { continue }
            let root = bundleURL.standardizedFileURL.path
            let identity = app.bundleIdentifier ?? root
            if seenIdentity.contains(identity) { continue }
            seenIdentity.insert(identity)
            var seenPid = Set<Int32>()
            let members = processes.filter { proc in
                let joins: Bool
                if !proc.path.isEmpty {
                    joins = proc.path.hasPrefix(root + "/")
                } else if let bundle = proc.bundleIdentifier, !bundle.isEmpty {
                    joins = bundle == app.bundleIdentifier
                } else {
                    joins = false
                }
                guard joins else { return false }
                return seenPid.insert(proc.pid).inserted
            }
            guard !members.isEmpty else { continue }
            members.forEach { claimed.insert($0.pid) }
            let id = "app:\(identity)"
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

    /// Parents stay inside the ten-row window. Expanded children are extra rows
    /// the list scrolls to; they do not consume a parent slot.
    private static func nestedVisible(_ parents: [ListRow], filter: String) -> [ListRow] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [ListRow] = []
        var parentsKept = 0
        for parent in parents {
            if parentsKept >= rowCap { break }
            let childHits = parent.children.filter { matches($0.displayName, pid: $0.pid, filter: needle) }
            let parentHit = needle.isEmpty || matches(parent.title, pid: nil, filter: needle) || !childHits.isEmpty
            guard parentHit else { continue }
            out.append(parent)
            parentsKept += 1
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
