import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let appliedKey = "ram.didApplyDefaultLaunchAtLogin"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func applyDefault() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: appliedKey) {
            return
        }
        defaults.set(true, forKey: appliedKey)
        _ = try? SMAppService.mainApp.register()
    }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("RAM launch-at-login: \(error.localizedDescription)")
        }
    }
}
