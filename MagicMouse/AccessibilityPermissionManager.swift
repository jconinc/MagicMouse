import AppKit
import ApplicationServices
import OSLog

@MainActor
final class AccessibilityPermissionManager {
    private let logger = AppEnvironment.logger("Accessibility")
    private var isShowingAlert = false

    func isTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func presentAccessibilityAlert(reason: String? = nil) {
        guard isShowingAlert == false else { return }
        isShowingAlert = true
        defer { isShowingAlert = false }

        logger.warning("Accessibility permission not granted")
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Accessibility permission required"

        var informativeText = "MagicMouse needs Accessibility access to intercept mouse buttons and post keyboard shortcuts. Input Monitoring alone is not sufficient for a non-listen-only event tap."
        if let reason, reason.isEmpty == false {
            informativeText += "\n\n\(reason)"
        }
        alert.informativeText = informativeText

        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            logger.error("Failed to construct Accessibility settings URL")
            return
        }

        if NSWorkspace.shared.open(url) {
            logger.info("Opened Accessibility settings")
        } else {
            logger.error("Failed to open Accessibility settings")
        }
    }
}
