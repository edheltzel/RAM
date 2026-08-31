import Foundation
import Darwin

enum MemorySampler {
    static func snapshot() -> MemorySnapshot {
        let total = physicalMemory()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return .empty }

        let page = UInt64(getpagesize())
        let active = UInt64(stats.active_count) * page
        let speculative = UInt64(stats.speculative_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let purgeable = UInt64(stats.purgeable_count) * page
        let external = UInt64(stats.external_page_count) * page

        // Same split Stats uses for the RAM popup: used is occupancy minus reclaimable file-backed pages.
        let usedRaw = active + inactive + speculative + wired + compressed
        let reclaimable = purgeable + external
        let used = usedRaw > reclaimable ? usedRaw - reclaimable : 0
        let free = total > used ? total - used : 0
        let app = used > (wired + compressed) ? used - wired - compressed : 0

        let pressureLevel = vmPressureLevel()
        return MemorySnapshot(
            total: total,
            used: used,
            free: free,
            app: app,
            wired: wired,
            compressed: compressed,
            swap: swapUsed(),
            pressureSysctl: pressureLevel,
            pressure: PressureLevel.from(sysctl: pressureLevel),
            sampledAt: Date()
        )
    }

    private static func physicalMemory() -> UInt64 {
        var info = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_info(mach_host_self(), HOST_BASIC_INFO, rebound, &count)
            }
        }
        if kr == KERN_SUCCESS { return UInt64(info.max_mem) }
        return ProcessInfo.processInfo.physicalMemory
    }

    private static func vmPressureLevel() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rc = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return rc == 0 ? Int(level) : 0
    }

    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let rc = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        return rc == 0 ? UInt64(usage.xsu_used) : 0
    }
}
