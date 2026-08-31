import Foundation
import AppKit

enum PressureLevel: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// kern.memorystatus_vm_pressure_level: 1 green, 2 orange, 4 red; 0 treated as green/normal.
    static func from(sysctl value: Int) -> PressureLevel {
        switch value {
        case 2: return .warning
        case 4: return .critical
        default: return .normal
        }
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    var color: NSColor {
        switch self {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    var segmentIndex: Int {
        switch self {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}

struct MemorySnapshot: Equatable, Sendable {
    var total: UInt64
    var used: UInt64
    var free: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var pressureSysctl: Int
    var pressure: PressureLevel
    var sampledAt: Date

    static let empty = MemorySnapshot(
        total: 1, used: 0, free: 1, app: 0, wired: 0, compressed: 0,
        pressureSysctl: 0, pressure: .normal, sampledAt: .distantPast
    )

    /// Chip percent is (total − free) / total.
    var usedPercent: Int {
        guard total > 0 else { return 0 }
        return Int((Double(total - free) / Double(total) * 100.0).rounded())
    }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return Double(total - free) / Double(total)
    }
}

struct Proc: Identifiable, Sendable, Equatable {
    var pid: Int32
    var ppid: Int32
    var name: String
    var path: String
    var argv0: String
    var bytes: UInt64
    var ttyDev: UInt32
    var bundleIdentifier: String?

    var id: Int32 { pid }

    var displayName: String {
        name.isEmpty ? "pid \(pid)" : name
    }
}

enum ListView: String, CaseIterable, Identifiable, Sendable {
    case app = "App"
    case process = "Process"
    case nested = "Nested"
    case session = "Session"
    case workload = "Workload"

    var id: String { rawValue }

    var next: ListView {
        let all = Self.allCases
        let idx = all.firstIndex(of: self).map { all.index(after: $0) } ?? all.startIndex
        return idx == all.endIndex ? all[all.startIndex] : all[idx]
    }
}

enum WorkloadKind: String, CaseIterable, Sendable {
    case claudeCode = "Claude Code"
    case grokBuild = "Grok Build"
    case pi = "Pi"
    case cursorAgent = "Cursor agent"

    /// Closed list: exact last-path-component / comm / argv0 match. Not fuzzy. Not "any child of a terminal".
    static func match(path: String, argv0: String, comm: String) -> WorkloadKind? {
        let tokens = [path, argv0, comm]
            .flatMap { $0.split(separator: " ").map(String.init) }
            .map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
        for token in tokens {
            switch token {
            case "claude": return .claudeCode
            case "grok": return .grokBuild
            case "pi": return .pi
            case "cursor-agent": return .cursorAgent
            default: break
            }
        }
        return nil
    }
}

enum RowKind: Equatable, Sendable {
    case process(pid: Int32)
    case group
}

struct ListRow: Identifiable, Equatable {
    var id: String
    var title: String
    var bytes: UInt64
    var kind: RowKind
    var depth: Int
    var expandable: Bool
    var expanded: Bool
    var children: [Proc]
}

enum ByteFormat {
    static func memory(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        let kib = 1024.0
        let mib = kib * 1024
        let gib = mib * 1024
        if b >= gib { return String(format: "%.2f GB", b / gib) }
        if b >= mib { return String(format: "%.0f MB", b / mib) }
        if b >= kib { return String(format: "%.0f KB", b / kib) }
        return "\(bytes) B"
    }
}

enum Palette {
    static let app = NSColor.systemBlue
    static let wired = NSColor.systemOrange
    static let compressed = NSColor.systemPink
    static let free = NSColor.systemGray
}
