import Foundation
import AppKit

enum ActivityMonitorOpener {
    /// Opens Activity Monitor. Jumping to the Memory tab is AppleScript (often needs
    /// Automation TCC). We never request that permission; if the jump fails, say so.
    @discardableResult
    static func open() -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Activity Monitor"]
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return "Could not open Activity Monitor."
        }

        if jumpToMemoryTab() {
            return "Opened Activity Monitor, Memory tab."
        }
        return "Opened Activity Monitor — click the Memory tab if it didn’t switch."
    }

    private static func jumpToMemoryTab() -> Bool {
        let source = """
        tell application "Activity Monitor" to activate
        delay 0.4
        try
            tell application "System Events"
                tell process "Activity Monitor"
                    click menu item "Memory" of menu "View" of menu bar 1
                    return true
                end tell
            end tell
        on error
            return false
        end try
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if error != nil { return false }
        return result.booleanValue
    }
}
