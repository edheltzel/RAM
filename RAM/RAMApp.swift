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
struct ChipLabel: View {
    var percent: Int

    /// Three discrete steps from the existing used-percent bands.
    private var gaugeValue: Double {
        if percent < 30 { return 0.33 }
        if percent < 60 { return 0.66 }
        return 1.0
    }

    private var tint: Color {
        if percent < 30 { return .white }
        if percent < 60 { return Color(nsColor: .systemBlue) }
        return Color(nsColor: .systemRed)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.open.with.lines.needle.33percent", variableValue: gaugeValue)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .symbolEffect(.variableColor, value: gaugeValue)
            Text("\(percent)%")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(tint)
        }
        .animation(.easeInOut(duration: 0.35), value: gaugeValue)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("RAM \(percent)%")
        .help("RAM \(percent)%")
    }
}
