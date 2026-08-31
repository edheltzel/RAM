import Foundation
import AppKit

enum Grouping {
    static let rowCap = 10

    static func rows(
        view: ListView,
        processes: [Proc],
        filter: String,
        expanded: Set<String>
    ) -> [ListRow] {
        switch view {
        case .process:
            return cap(filterRows(processes.map(processRow), filter: filter))
        case .app:
            return cap(filterRows(appRows(processes, nested: false, expanded: []), filter: filter))
        case .nested:
            return nestedVisible(appRows(processes, nested: true, expanded: expanded), filter: filter)
        case .session:
            return cap(filterRows(sessionRows(processes), filter: filter))
        case .workload:
            return cap(filterRows(workloadRows(processes), filter: filter))
        }
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
    private static func appRows(_ processes: [Proc], nested: Bool, expanded: Set<String>) -> [ListRow] {
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
                    children: members.sorted { $0.bytes > $1.bytes }
                )
            )
        }

        for proc in processes where !claimed.contains(proc.pid) {
            rows.append(processRow(proc))
        }
        return rows.sorted { $0.bytes > $1.bytes }
    }

    private static func nestedVisible(_ parents: [ListRow], filter: String) -> [ListRow] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out: [ListRow] = []
        for parent in parents {
            if out.count >= rowCap { break }
            let childHits = parent.children.filter { matches($0.displayName, pid: $0.pid, filter: needle) }
            let parentHit = needle.isEmpty || matches(parent.title, pid: nil, filter: needle) || !childHits.isEmpty
            guard parentHit else { continue }
            out.append(parent)
            if parent.expandable && parent.expanded {
                let kids = needle.isEmpty ? parent.children : childHits
                for child in kids {
                    if out.count >= rowCap { break }
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

    /// Session grouping, best-effort, no TCC:
    /// 1. Processes that share a controlling TTY (`proc_bsdinfo.pbi_tdev != 0`) are one session.
    /// 2. If a process has no TTY, walk `ppid` until an ancestor with a TTY is found and inherit it.
    /// 3. If still none, walk `ppid` until a known terminal-emulator bundle (Terminal, iTerm2,
    ///    Ghostty, Warp, Alacritty, kitty, WezTerm) or Cursor's `pty-host`; that ancestor pid is
    ///    the session key.
    /// 4. Remaining GUI helpers stay with their owning app pid; leftover daemons are their own pid.
    private static func sessionRows(_ processes: [Proc]) -> [ListRow] {
        let byPid = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var sessionKey: [Int32: String] = [:]

        func key(for proc: Proc, seen: Set<Int32> = []) -> String {
            if let cached = sessionKey[proc.pid] { return cached }
            if seen.contains(proc.pid) { return "pid:\(proc.pid)" }
            var seen = seen
            seen.insert(proc.pid)

            if proc.ttyDev != 0 {
                let k = "tty:\(proc.ttyDev)"
                sessionKey[proc.pid] = k
                return k
            }
            if let parent = byPid[proc.ppid] {
                if parent.ttyDev != 0 {
                    let k = "tty:\(parent.ttyDev)"
                    sessionKey[proc.pid] = k
                    return k
                }
                if isTerminalEmulator(parent) {
                    let k = "term:\(parent.pid)"
                    sessionKey[proc.pid] = k
                    return k
                }
                let k = key(for: parent, seen: seen)
                sessionKey[proc.pid] = k
                return k
            }
            if isTerminalEmulator(proc) {
                let k = "term:\(proc.pid)"
                sessionKey[proc.pid] = k
                return k
            }
            let k = "pid:\(proc.pid)"
            sessionKey[proc.pid] = k
            return k
        }

        var buckets: [String: [Proc]] = [:]
        for proc in processes {
            buckets[key(for: proc), default: []].append(proc)
        }

        return buckets.map { key, members in
            let sorted = members.sorted { $0.bytes > $1.bytes }
            let title = sessionTitle(key: key, members: sorted)
            return ListRow(
                id: "sess:\(key)",
                title: title,
                bytes: members.reduce(0) { $0 + $1.bytes },
                kind: .group,
                depth: 0,
                expandable: false,
                expanded: false,
                children: sorted
            )
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private static func sessionTitle(key: String, members: [Proc]) -> String {
        if let emulator = members.first(where: isTerminalEmulator) {
            return emulator.displayName
        }
        if key.hasPrefix("tty:"), let head = members.first {
            return "TTY · \(head.displayName)"
        }
        if members.count == 1 { return members[0].displayName }
        return members[0].displayName + " +\(members.count - 1)"
    }

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    private static func isTerminalEmulator(_ proc: Proc) -> Bool {
        if let bid = proc.bundleIdentifier, terminalBundleIDs.contains(bid) { return true }
        let base = URL(fileURLWithPath: proc.path).lastPathComponent.lowercased()
        if ["terminal", "iterm2", "ghostty", "warp", "alacritty", "kitty", "wezterm"].contains(base) {
            return true
        }
        let name = proc.name.lowercased()
        if name.contains("pty-host") { return true }
        return false
    }

    private static func workloadRows(_ processes: [Proc]) -> [ListRow] {
        var buckets: [WorkloadKind: [Proc]] = [:]
        for proc in processes {
            let comm = URL(fileURLWithPath: proc.path).lastPathComponent
            if let kind = WorkloadKind.match(path: proc.path, argv0: proc.argv0, comm: comm.isEmpty ? proc.name : comm) {
                buckets[kind, default: []].append(proc)
            }
        }
        return WorkloadKind.allCases.compactMap { kind in
            guard let members = buckets[kind], !members.isEmpty else { return nil }
            return ListRow(
                id: "wl:\(kind.rawValue)",
                title: kind.rawValue,
                bytes: members.reduce(0) { $0 + $1.bytes },
                kind: .group,
                depth: 0,
                expandable: false,
                expanded: false,
                children: members.sorted { $0.bytes > $1.bytes }
            )
        }
        .sorted { $0.bytes > $1.bytes }
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
