import CoreGraphics
import Foundation
import OSLog

@MainActor
final class ActionDispatcher {
    private let logger = AppEnvironment.logger("ActionDispatcher")

    func perform(_ action: ButtonAction) {
        guard let shortcut = action.shortcut else { return }
        post(shortcut: shortcut, actionName: action.loggingName)
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

    private func post(shortcut: KeyboardShortcut, actionName: String) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            logger.error("Failed to create synthetic keyboard events for \(actionName, privacy: .public)")
            return
        }

        keyDown.flags = shortcut.modifiers
        keyUp.flags = shortcut.modifiers

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.info("Posted action \(actionName, privacy: .public) using key code \(shortcut.keyCode, privacy: .public)")
    }
}
