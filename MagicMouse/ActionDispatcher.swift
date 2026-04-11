import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class ActionDispatcher {
    private let logger = AppEnvironment.logger("ActionDispatcher")

    func perform(_ action: ButtonAction) {
        guard let shortcut = action.shortcut else { return }
        postDirect(shortcut: shortcut, actionName: action.loggingName)
    }

    /// Post key events through the CGEventTap proxy. This is the most reliable
    /// method — events posted via the proxy bypass our own tap and go straight
    /// to the system, using only the Accessibility permission we already have.
    func performViaProxy(_ action: ButtonAction, proxy: CGEventTapProxy) {
        guard let shortcut = action.shortcut else { return }
        postViaProxy(shortcut: shortcut, proxy: proxy, actionName: action.loggingName)
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

    // MARK: - Proxy-based posting (preferred)

    private func postViaProxy(shortcut: KeyboardShortcut, proxy: CGEventTapProxy, actionName: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create event source for \(actionName, privacy: .public)")
            return
        }

        // Post modifier key down
        if shortcut.modifiers.contains(.maskControl) {
            postKeyViaProxy(source: source, proxy: proxy, keyCode: CGKeyCode(kVK_Control), keyDown: true, flags: .maskControl)
        }

        // Post main key down + up with modifier flags
        postKeyViaProxy(source: source, proxy: proxy, keyCode: shortcut.keyCode, keyDown: true, flags: shortcut.modifiers)
        postKeyViaProxy(source: source, proxy: proxy, keyCode: shortcut.keyCode, keyDown: false, flags: shortcut.modifiers)

        // Post modifier key up
        if shortcut.modifiers.contains(.maskControl) {
            postKeyViaProxy(source: source, proxy: proxy, keyCode: CGKeyCode(kVK_Control), keyDown: false, flags: [])
        }

        logger.info("Posted action \(actionName, privacy: .public) via proxy")
    }

    private func postKeyViaProxy(source: CGEventSource, proxy: CGEventTapProxy, keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        event.tapPostEvent(proxy)
    }

    // MARK: - Direct posting (fallback)

    private func postDirect(shortcut: KeyboardShortcut, actionName: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create event source for \(actionName, privacy: .public)")
            return
        }

        // Control key down
        if shortcut.modifiers.contains(.maskControl) {
            if let ctrlDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: true) {
                ctrlDown.flags = .maskControl
                ctrlDown.post(tap: .cghidEventTap)
            }
        }

        // Main key down + up
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) {
            keyDown.flags = shortcut.modifiers
            keyUp.flags = shortcut.modifiers
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }

        // Control key up
        if shortcut.modifiers.contains(.maskControl) {
            if let ctrlUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: false) {
                ctrlUp.flags = []
                ctrlUp.post(tap: .cghidEventTap)
            }
        }

        logger.info("Posted action \(actionName, privacy: .public) direct")
    }
}
