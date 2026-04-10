import CoreGraphics
import Foundation
import OSLog

@MainActor
final class EventTapSupervisor {
    private static let eventMask: CGEventMask =
        (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) |
        (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)

    private let logger = AppEnvironment.logger("EventTap")
    private let appModel: AppModel
    private let permissionManager: AccessibilityPermissionManager
    private let actionDispatcher: ActionDispatcher
    private let onLearnedButton: (Int) -> Void
    private let onPermissionAlertRequested: (String) -> Void
    private let onTapFailureAlertRequested: (String) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?
    private var suppressedButtons = Set<Int>()
    private var sessionIsActive = true
    private var creationFailures = 0
    private var retriesExhausted = false
    private var lastKnownTrustState: Bool?
    private var lastProbeDate = Date.distantPast
    private var hasPresentedPermissionAlert = false
    private var hasPresentedTapFailureAlert = false

    init(
        appModel: AppModel,
        permissionManager: AccessibilityPermissionManager,
        actionDispatcher: ActionDispatcher,
        onLearnedButton: @escaping (Int) -> Void,
        onPermissionAlertRequested: @escaping (String) -> Void,
        onTapFailureAlertRequested: @escaping (String) -> Void
    ) {
        self.appModel = appModel
        self.permissionManager = permissionManager
        self.actionDispatcher = actionDispatcher
        self.onLearnedButton = onLearnedButton
        self.onPermissionAlertRequested = onPermissionAlertRequested
        self.onTapFailureAlertRequested = onTapFailureAlertRequested
    }

    func start() {
        startWatchdogIfNeeded()
        evaluateState(showPermissionPrompt: true, reason: "launch")
    }

    func stop() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        tearDownTap()
    }

    func handleAppDidBecomeActive() {
        resetCreationFailures()
        evaluateState(showPermissionPrompt: false, reason: "app became active")
    }

    func settingsDidChange(triggerPermissionPrompt: Bool) {
        if appModel.isEnabled == false {
            appModel.cancelLearningButton()
            appModel.setWarning(nil)
            resetCreationFailures()
            tearDownTap()
            return
        }

        if triggerPermissionPrompt {
            hasPresentedPermissionAlert = false
        }

        evaluateState(showPermissionPrompt: triggerPermissionPrompt, reason: "settings changed")
    }

    func setSessionActive(_ isActive: Bool) {
        guard sessionIsActive != isActive else { return }
        sessionIsActive = isActive

        if isActive {
            logger.info("Session became active; resuming event tap supervision")
            resetCreationFailures()
            evaluateState(showPermissionPrompt: false, reason: "session became active")
        } else {
            logger.info("Session resigned active; pausing event tap")
            tearDownTap()
        }
    }

    func handleWakeFromSleep() {
        logger.info("System wake detected")
        resetCreationFailures()
        evaluateState(showPermissionPrompt: false, reason: "wake from sleep")
    }

    private func startWatchdogIfNeeded() {
        guard watchdogTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
        timer.tolerance = 1
        watchdogTimer = timer
    }

    private func watchdogTick() {
        evaluateState(showPermissionPrompt: false, reason: "watchdog")

        guard sessionIsActive, appModel.isEnabled, let eventTap else {
            return
        }

        if Date().timeIntervalSince(lastProbeDate) >= 30 {
            lastProbeDate = Date()
            if actionDispatcher.postWatchdogProbe() == false {
                logger.warning("Watchdog probe failed to post null event; recreating tap")
                recreateTap(reason: "watchdog probe failed")
                return
            }
        }

        if CGEvent.tapIsEnabled(tap: eventTap) == false {
            logger.warning("Watchdog detected disabled tap; recreating")
            recreateTap(reason: "watchdog detected disabled tap")
        }
    }

    private func evaluateState(showPermissionPrompt: Bool, reason: String) {
        let trusted = permissionManager.isTrusted(prompt: false)
        let previousTrustState = lastKnownTrustState
        lastKnownTrustState = trusted

        if trusted, previousTrustState == false {
            logger.info("Accessibility permission restored")
            hasPresentedPermissionAlert = false
            resetCreationFailures()
        }

        guard appModel.isEnabled else {
            appModel.setWarning(nil)
            tearDownTap()
            return
        }

        guard sessionIsActive else {
            tearDownTap()
            return
        }

        guard trusted else {
            tearDownTap()
            let message = "Accessibility permission is required. If macOS reset or revoked it, re-enable MagicMouse in System Settings > Privacy & Security > Accessibility."
            appModel.setWarning(message)

            if showPermissionPrompt || previousTrustState == true {
                requestPermissionAlert(message)
            }
            return
        }

        if eventTap == nil {
            attemptCreateTap(reason: reason)
        }
    }

    private func attemptCreateTap(reason: String) {
        guard retriesExhausted == false else {
            return
        }

        // Unretained is safe: AppDelegate owns this instance for the app lifetime
        // and tearDownTap() invalidates the port before deallocation.
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            // Swift 6 migration: this @convention(c) callback calls @MainActor methods.
            // It runs on the main thread (source is on the main run loop) so it is safe,
            // but Swift 6 will require `nonisolated` + `MainActor.assumeIsolated`.
            callback: { proxy, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let supervisor = Unmanaged<EventTapSupervisor>.fromOpaque(userInfo).takeUnretainedValue()
                return supervisor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            recordCreationFailure("Failed to create event tap during \(reason)")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            recordCreationFailure("Created event tap but failed to create its run loop source")
            CFMachPortInvalidate(eventTap)
            return
        }

        self.eventTap = eventTap
        runLoopSource = source
        suppressedButtons.removeAll()
        lastProbeDate = Date()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        resetCreationFailures()
        appModel.setWarning(nil)
        logger.info("Event tap installed on the main run loop")
    }

    private func recreateTap(reason: String) {
        logger.info("Recreating event tap because \(reason, privacy: .public)")
        tearDownTap()
        resetCreationFailures()
        attemptCreateTap(reason: reason)
    }

    private func tearDownTap() {
        suppressedButtons.removeAll()

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            logger.info("Event tap stopped")
        }
    }

    private func resetCreationFailures() {
        creationFailures = 0
        retriesExhausted = false
        hasPresentedTapFailureAlert = false
    }

    private func recordCreationFailure(_ message: String) {
        creationFailures += 1
        logger.error("\(message, privacy: .public); attempt \(creationFailures, privacy: .public) of 3")

        guard creationFailures >= 3 else {
            return
        }

        retriesExhausted = true
        let warningMessage = "MagicMouse could not create its event tap after 3 attempts. The most common cause is missing or reset Accessibility permission. Check System Settings and Console.app logs filtered by com.local.mouseremap."
        appModel.setWarning(warningMessage)
        if hasPresentedTapFailureAlert == false {
            hasPresentedTapFailureAlert = true
            onTapFailureAlertRequested(warningMessage)
        }
    }

    private func requestPermissionAlert(_ message: String) {
        guard hasPresentedPermissionAlert == false else { return }
        hasPresentedPermissionAlert = true
        onPermissionAlertRequested(message)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            logger.warning("Event tap disabled by timeout; re-enabling")
            reenableTap()
            return Unmanaged.passUnretained(event)

        case .tapDisabledByUserInput:
            logger.warning("Event tap disabled by user input; re-enabling")
            reenableTap()
            return Unmanaged.passUnretained(event)

        case .otherMouseDown:
            return handleMouseButtonDown(event)

        case .otherMouseUp:
            return handleMouseButtonUp(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleMouseButtonDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard AppEnvironment.supportedButtonRange.contains(buttonNumber) else {
            return Unmanaged.passUnretained(event)
        }

        appModel.recordObservedButton(buttonNumber)

        if appModel.captureLearnedButton(buttonNumber) {
            suppressedButtons.insert(buttonNumber)
            logger.info("Learned mouse button \(buttonNumber, privacy: .public)")
            onLearnedButton(buttonNumber)
            return nil
        }

        let action = appModel.effectiveAction(forPhysicalButton: buttonNumber)
        guard action.handlesEvent else {
            return Unmanaged.passUnretained(event)
        }

        suppressedButtons.insert(buttonNumber)
        logger.info("Handled mouse button \(buttonNumber, privacy: .public) with action \(action.loggingName, privacy: .public)")
        actionDispatcher.perform(action)
        return nil
    }

    private func handleMouseButtonUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        guard AppEnvironment.supportedButtonRange.contains(buttonNumber) else {
            return Unmanaged.passUnretained(event)
        }

        if suppressedButtons.remove(buttonNumber) != nil {
            logger.debug("Swallowed mouse button \(buttonNumber, privacy: .public) up")
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func reenableTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}
