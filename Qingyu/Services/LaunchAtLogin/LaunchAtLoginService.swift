import Foundation
import ServiceManagement

protocol LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginService: LaunchAtLoginServiceProtocol {
    /// `SMAppService` (and therefore `SMAppService.mainApp`) is available from
    /// macOS 13. On macOS 12 the service reports itself as unavailable and
    /// `setEnabled(_:)` is a no-op, so the rest of the app keeps working.
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
