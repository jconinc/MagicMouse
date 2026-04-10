import AppKit
import OSLog
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    private let logger = AppEnvironment.logger("LaunchAtLogin")
    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    var toggleState: NSControl.StateValue {
        isEnabled ? .on : .off
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
            logger.info("Launch at Login enabled")
        } else {
            try service.unregister()
            logger.info("Launch at Login disabled")
        }
    }
}
