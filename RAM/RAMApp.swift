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

/// Menu-bar extra: filled memorychip + percent. Pressure colors the chip. Not text-only.
struct ChipLabel: View {
    var percent: Int
    var pressure: PressureLevel

    var body: some View {
        Image(nsImage: Self.image(percent: percent, color: pressure.color))
            .renderingMode(.original)
            .accessibilityLabel("RAM \(percent) percent, \(pressure.title)")
            .help("RAM \(percent)%")
    }

    private static func image(percent: Int, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        let symbol = NSImage(systemSymbolName: "memorychip.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()
        let iconSize = symbol.size

        let text = "\(percent)%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let gap: CGFloat = 4
        let height: CGFloat = 24
        let width = ceil(iconSize.width) + gap + ceil(textSize.width) + 2
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let iconY = (rect.height - iconSize.height) / 2
            symbol.draw(
                at: NSPoint(x: 1, y: iconY),
                from: NSRect(origin: .zero, size: iconSize),
                operation: .sourceOver,
                fraction: 1
            )
            let textY = (rect.height - textSize.height) / 2
            (text as NSString).draw(
                at: NSPoint(x: 1 + iconSize.width + gap, y: textY),
                withAttributes: attrs
            )
            return true
        }
        image.isTemplate = false
        return image
    }
}
