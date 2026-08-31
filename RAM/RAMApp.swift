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
            ChipLabel(percent: store.memory.usedPercent)
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

/// Menu-bar extra: one gauge + percent. Color follows used percent (white / systemBlue / red at 60%+).
/// MenuBarExtra templates SwiftUI labels, so rasterize original or both glyph and percent go monochrome.
struct ChipLabel: View {
    var percent: Int

    var body: some View {
        Image(nsImage: Self.makeImage(percent: percent))
            .renderingMode(.original)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("RAM \(percent)%")
            .help("RAM \(percent)%")
    }

    private static func tint(percent: Int) -> Color {
        if percent < 30 { return .white }
        if percent < 60 { return Color(nsColor: .systemBlue) }
        return Color(nsColor: .systemRed)
    }

    @MainActor
    static func makeImage(percent: Int) -> NSImage {
        let color = tint(percent: percent)
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
