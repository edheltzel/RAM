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

struct ChipLabel: View {
    var percent: Int
    var pressure: PressureLevel

    var body: some View {
        Image(nsImage: Self.image(percent: percent, color: pressure.color))
            .renderingMode(.original)
    }

    private static func image(percent: Int, color: NSColor) -> NSImage {
        let text = "RAM \(percent)%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let size = NSSize(width: ceil(textSize.width) + 2, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            (text as NSString).draw(
                at: NSPoint(x: 1, y: (rect.height - textSize.height) / 2),
                withAttributes: attrs
            )
            return true
        }
        image.isTemplate = false
        return image
    }
}
