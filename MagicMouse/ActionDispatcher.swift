import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class ActionDispatcher {
    private let logger = AppEnvironment.logger("ActionDispatcher")

    func perform(_ action: ButtonAction) {
        guard let shortcut = action.shortcut else { return }
        postViaAppleScript(shortcut: shortcut, actionName: action.loggingName)
    }

    @discardableResult
    func postWatchdogProbe() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let nullEvent = CGEvent(source: source) else {
            logger.error("Failed to create watchdog null event")
            return false
        }

        nullEvent.post(tap: .cghidEventTap)
        logger.debug("Posted watchdog null event")
        return true
    }

    // MARK: - AppleScript approach

    /// Use System Events to send keystrokes. This bypasses CGEvent restrictions
    /// on newer macOS versions where synthetic HID events don't trigger
    /// Mission Control shortcuts.
    private func postViaAppleScript(shortcut: KeyboardShortcut, actionName: String) {
        var modifierList: [String] = []
        if shortcut.modifiers.contains(.maskControl) { modifierList.append("control down") }
        if shortcut.modifiers.contains(.maskCommand) { modifierList.append("command down") }
        if shortcut.modifiers.contains(.maskAlternate) { modifierList.append("option down") }
        if shortcut.modifiers.contains(.maskShift) { modifierList.append("shift down") }

        let modifiers = modifierList.isEmpty ? "" : " using {\(modifierList.joined(separator: ", "))}"
        let script = "tell application \"System Events\" to key code \(shortcut.keyCode)\(modifiers)"

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error {
                logger.error("AppleScript failed for \(actionName, privacy: .public): \(error, privacy: .public)")
            } else {
                logger.info("Posted action \(actionName, privacy: .public) via AppleScript")
            }
        }
    }
}
