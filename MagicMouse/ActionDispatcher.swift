import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

@MainActor
final class ActionDispatcher {
    private let logger = AppEnvironment.logger("ActionDispatcher")

    func perform(_ action: ButtonAction) {
        guard let shortcut = action.shortcut else { return }
        postViaOsascript(shortcut: shortcut, actionName: action.loggingName)
    }

    /// Also called from EventTapSupervisor with the proxy — but we don't use
    /// the proxy anymore since proxy-posted events go to the app, not the system.
    func performViaProxy(_ action: ButtonAction, proxy: CGEventTapProxy) {
        perform(action)
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

    // MARK: - osascript subprocess

    /// Shell out to /usr/bin/osascript to send keystrokes via System Events.
    /// This is the only method confirmed to trigger Mission Control shortcuts
    /// on macOS 26. osascript as a system binary may have implicit trust for
    /// System Events automation.
    private func postViaOsascript(shortcut: KeyboardShortcut, actionName: String) {
        var modifierList: [String] = []
        if shortcut.modifiers.contains(.maskControl) { modifierList.append("control down") }
        if shortcut.modifiers.contains(.maskCommand) { modifierList.append("command down") }
        if shortcut.modifiers.contains(.maskAlternate) { modifierList.append("option down") }
        if shortcut.modifiers.contains(.maskShift) { modifierList.append("shift down") }

        let modifiers = modifierList.isEmpty ? "" : " using {\(modifierList.joined(separator: ", "))}"
        let script = "tell application \"System Events\" to key code \(shortcut.keyCode)\(modifiers)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            logger.info("Posted action \(actionName, privacy: .public) via osascript")
        } catch {
            logger.error("osascript failed for \(actionName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
