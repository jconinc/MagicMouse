import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class ActionDispatcher {
    private static let modifierKeyDefinitions: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
        (.maskCommand, CGKeyCode(kVK_Command)),
        (.maskShift, CGKeyCode(kVK_Shift)),
        (.maskAlternate, CGKeyCode(kVK_Option)),
        (.maskControl, CGKeyCode(kVK_Control))
    ]

    private static let supportedModifierFlags = CGEventFlags(rawValue: modifierKeyDefinitions.reduce(CGEventFlags.RawValue(0)) { partialResult, definition in
        partialResult | definition.flag.rawValue
    })

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
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create HID event source for \(actionName, privacy: .public)")
            return
        }

        let modifiers = CGEventFlags(rawValue: shortcut.modifiers.rawValue & Self.supportedModifierFlags.rawValue)
        let activeModifierDefinitions = Self.modifierKeyDefinitions.filter { modifiers.contains($0.flag) }
        var currentFlags = CGEventFlags()

        for definition in activeModifierDefinitions {
            currentFlags.insert(definition.flag)
            guard postKeyEvent(
                source: source,
                keyCode: definition.keyCode,
                isDown: true,
                flags: currentFlags
            ) else {
                logger.error("Failed to post modifier key down for \(actionName, privacy: .public)")
                return
            }
        }

        guard postKeyEvent(
            source: source,
            keyCode: shortcut.keyCode,
            isDown: true,
            flags: currentFlags
        ), postKeyEvent(
            source: source,
            keyCode: shortcut.keyCode,
            isDown: false,
            flags: currentFlags
        ) else {
            logger.error("Failed to post synthetic keyboard events for \(actionName, privacy: .public)")
            return
        }

        for definition in activeModifierDefinitions.reversed() {
            currentFlags.remove(definition.flag)
            guard postKeyEvent(
                source: source,
                keyCode: definition.keyCode,
                isDown: false,
                flags: currentFlags
            ) else {
                logger.error("Failed to post modifier key up for \(actionName, privacy: .public)")
                return
            }
        }

        logger.info("Posted action \(actionName, privacy: .public) using key code \(shortcut.keyCode, privacy: .public)")
    }

    private func postKeyEvent(
        source: CGEventSource,
        keyCode: CGKeyCode,
        isDown: Bool,
        flags: CGEventFlags
    ) -> Bool {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else {
            return false
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }
}
