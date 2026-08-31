import Foundation
import AppKit
import Darwin

enum ProcessSampler {
    static func list() -> [Proc] {
        let pids = allPids()
        let appsByPID = runningApps()
        var result: [Proc] = []
        result.reserveCapacity(pids.count)
        for pid in pids {
            if pid <= 0 { continue }
            guard let bytes = residentBytes(pid: pid) else { continue }
            if bytes == 0 { continue }
            let bsd = bsdInfo(pid: pid)
            let path = pidPath(pid: pid)
            let comm = bsd?.name ?? pidName(pid: pid)
            let argv0 = arguments0(pid: pid) ?? ""
            let app = appsByPID[pid]
            let display: String
            if let localized = app?.localizedName, !localized.isEmpty {
                display = localized
            } else if !path.isEmpty {
                display = URL(fileURLWithPath: path).lastPathComponent
            } else if !comm.isEmpty {
                display = comm
            } else {
                display = "pid \(pid)"
            }
            result.append(
                Proc(
                    pid: pid,
                    ppid: bsd?.ppid ?? 0,
                    name: display,
                    path: path,
                    argv0: argv0,
                    bytes: bytes,
                    ttyDev: bsd?.tdev ?? 0,
                    bundleIdentifier: app?.bundleIdentifier
                )
            )
        }
        return result
    }

    private struct BSD {
        var ppid: Int32
        var tdev: UInt32
        var name: String
    }

    private static func allPids() -> [Int32] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }
        let count = Int(bytesNeeded) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: count + 32)
        let filled = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.stride)
        )
        guard filled > 0 else { return [] }
        let n = Int(filled) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(n)).map { Int32($0) }
    }

    private static func residentBytes(pid: Int32) -> UInt64? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let got = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr, Int32(size))
        }
        guard got == Int32(size) else { return nil }
        return UInt64(info.pti_resident_size)
    }

    private static func bsdInfo(pid: Int32) -> BSD? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let got = withUnsafeMutablePointer(to: &info) { ptr in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, Int32(size))
        }
        guard got == Int32(size) else { return nil }
        let name = withUnsafeBytes(of: info.pbi_name) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return BSD(ppid: Int32(info.pbi_ppid), tdev: info.e_tdev, name: name)
    }

    private static func pidPath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func pidName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        let n = proc_name(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    /// argv0 only — never keep the rest of the vector (tokens often include secrets).
    private static func arguments0(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(argmax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var bufSize = buf.count
        guard sysctl(&mib, 3, &buf, &bufSize, nil, 0) == 0, bufSize > 4 else { return nil }
        // KERN_PROCARGS2: Int32 argc, then exec path, then argv0...
        var offset = MemoryLayout<Int32>.size
        while offset < bufSize && buf[offset] != 0 { offset += 1 }
        while offset < bufSize && buf[offset] == 0 { offset += 1 }
        guard offset < bufSize else { return nil }
        return String(cString: buf.withUnsafeBufferPointer { $0.baseAddress! + offset })
    }

    private static func runningApps() -> [Int32: NSRunningApplication] {
        var map: [Int32: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            map[app.processIdentifier] = app
        }
        return map
    }
}
