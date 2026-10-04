import SwiftUI
import AppKit

@main
struct RAMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PopupView()
                .environment(store)
        } label: {
            ChipLabel(percent: store.memory.usedPercent, pressure: store.memory.pressure)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let id = Bundle.main.bundleIdentifier ?? "app.ram.extra"
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        if copies.count > 1 {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Menu-bar extra: one gauge + percent.
/// Under 30% white, under 60% blue, and 60% or more follows memory pressure (green, orange, red).
/// The popup gauge stays on its own pressure colors.
/// MenuBarExtra templates SwiftUI labels, so rasterize original or both glyph and percent go monochrome.
struct ChipLabel: View {
    var percent: Int
    var pressure: PressureLevel

    var body: some View {
        Image(nsImage: Self.makeImage(percent: percent, pressure: pressure))
            .renderingMode(.original)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("RAM \(percent)%")
            .help("RAM \(percent)%")
    }

    /// Chip only. The popup gauge is not colored from these cuts.
    private static func tint(percent: Int, pressure: PressureLevel) -> Color {
        if percent < 30 { return .white }
        if percent < 60 { return .blue }
        switch pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    @MainActor
    static func makeImage(percent: Int, pressure: PressureLevel) -> NSImage {
        let color = tint(percent: percent, pressure: pressure)
        let content = HStack(spacing: 4) {
            Image(systemName: "gauge.open.with.lines.needle.33percent")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
        }
        .fixedSize()

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            image.isTemplate = false
            return image
        }
        let fallback = NSImage(systemSymbolName: "gauge.open.with.lines.needle.33percent", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = false
        return fallback
    }
}
