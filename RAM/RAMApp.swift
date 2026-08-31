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

/// Menu-bar extra: black/clear SF Symbol, system tints. Bar is 24 pt.
struct ChipLabel: View {
    var percent: Int
    var pressure: PressureLevel

    var body: some View {
        Image(systemName: "memorychip")
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: .medium))
            .frame(height: 24)
            .accessibilityLabel("RAM \(percent) percent, \(pressure.title)")
            .help("RAM \(percent)%")
    }
}
