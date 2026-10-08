import Foundation
import ServiceManagement

protocol LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

final class LaunchAtLoginService: LaunchAtLoginServiceProtocol {
    func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
