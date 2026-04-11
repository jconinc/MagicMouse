import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = AppEnvironment.logger("App")
    private let appModel = AppModel.shared
    private let permissionManager = AccessibilityPermissionManager()
    private let actionDispatcher = ActionDispatcher()
    private let launchAtLoginManager = LaunchAtLoginManager()

    private lazy var eventTapSupervisor = EventTapSupervisor(
        appModel: appModel,
        permissionManager: permissionManager,
        actionDispatcher: actionDispatcher,
        onLearnedButton: { [weak self] buttonNumber in
            self?.presentLearnedButtonAlert(buttonNumber)
        },
        onPermissionAlertRequested: { [weak self] message in
            self?.permissionManager.presentAccessibilityAlert(reason: message)
        },
        onTapFailureAlertRequested: { [weak self] message in
            self?.presentAlert(
                message: "Mouse remap unavailable",
                informativeText: message
            )
        }
    )

    private var statusItem: NSStatusItem?
    private var warningMenuItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var learnButtonMenuItem: NSMenuItem?
    private var preferencesMenuItem: NSMenuItem?
    private var swapButtonsMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logOperatingSystemVersion()
        buildStatusItem()
        bindModel()
        installWorkspaceObservers()
        refreshMenuState()
        updateStatusIcon()
        requestAutomationPermission()
        eventTapSupervisor.start()
    }

    /// Trigger the Automation permission prompt by sending a no-op Apple Event
    /// to System Events. macOS will show the "wants to control System Events"
    /// dialog if permission hasn't been granted yet.
    private func requestAutomationPermission() {
        let script = NSAppleScript(source: """
            tell application "System Events" to return 1
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            logger.warning("Automation permission not yet granted: \(error, privacy: .public)")
        } else {
            logger.info("Automation permission granted")
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        eventTapSupervisor.handleAppDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        eventTapSupervisor.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let warningItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warningItem.isHidden = true
        warningItem.isEnabled = false

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabledItem.target = self

        let learnItem = NSMenuItem(title: "Learn button", action: #selector(toggleLearning(_:)), keyEquivalent: "")
        learnItem.target = self

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self

        let swapButtonsItem = NSMenuItem(title: "Swap buttons", action: #selector(toggleSwapButtons(_:)), keyEquivalent: "")
        swapButtonsItem.target = self

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLoginItem.target = self

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(warningItem)
        menu.addItem(enabledItem)
        menu.addItem(learnItem)
        menu.addItem(preferencesItem)
        menu.addItem(swapButtonsItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        item.menu = menu

        statusItem = item
        warningMenuItem = warningItem
        enabledMenuItem = enabledItem
        learnButtonMenuItem = learnItem
        preferencesMenuItem = preferencesItem
        swapButtonsMenuItem = swapButtonsItem
        launchAtLoginMenuItem = launchAtLoginItem
    }

    private func bindModel() {
        appModel.$warningMessage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshMenuState()
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)

        appModel.$isLearningButton
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshMenuState()
            }
            .store(in: &cancellables)

        appModel.$isEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshMenuState()
            }
            .store(in: &cancellables)

        appModel.$swapButtons
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.refreshMenuState()
            }
            .store(in: &cancellables)
    }

    private func installWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func refreshMenuState() {
        warningMenuItem?.title = appModel.warningMessage ?? ""
        warningMenuItem?.isHidden = appModel.warningMessage == nil
        enabledMenuItem?.state = appModel.isEnabled ? .on : .off
        learnButtonMenuItem?.title = appModel.isLearningButton ? "Cancel learn button" : "Learn button"
        swapButtonsMenuItem?.state = appModel.swapButtons ? .on : .off
        launchAtLoginMenuItem?.state = launchAtLoginManager.toggleState
        preferencesMenuItem?.isEnabled = true
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let symbolName = appModel.warningMessage == nil ? "cursorarrow.click.2" : "exclamationmark.triangle.fill"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MagicMouse")
        button.image?.isTemplate = true
        button.toolTip = appModel.warningMessage ?? "MagicMouse"
    }

    private func logOperatingSystemVersion() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = AppEnvironment.versionString(version)
        logger.info("Launching on macOS \(versionString, privacy: .public)")

        if version.majorVersion > AppEnvironment.validatedThroughMajorVersion {
            logger.warning("Running on newer macOS \(versionString, privacy: .public) than the current validation ceiling (\(AppEnvironment.validatedThroughMajorVersion, privacy: .public)); continuing with public API implementation")
        }
    }

    @objc
    private func toggleEnabled(_ sender: NSMenuItem) {
        appModel.isEnabled.toggle()
        eventTapSupervisor.settingsDidChange(triggerPermissionPrompt: appModel.isEnabled)
    }

    @objc
    private func toggleSwapButtons(_ sender: NSMenuItem) {
        appModel.swapButtons.toggle()
        eventTapSupervisor.settingsDidChange(triggerPermissionPrompt: false)
    }

    @objc
    private func toggleLearning(_ sender: NSMenuItem) {
        if appModel.isLearningButton {
            appModel.cancelLearningButton()
        } else {
            appModel.beginLearningButton()
            openPreferences(nil)
        }
    }

    private var settingsWindow: NSWindow?

    @objc
    private func openPreferences(_ sender: Any?) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(model: AppModel.shared)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MagicMouse Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 400))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc
    private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            try launchAtLoginManager.setEnabled(launchAtLoginManager.isEnabled == false)
            refreshMenuState()
        } catch {
            presentAlert(
                message: "Could not update Launch at Login",
                informativeText: error.localizedDescription
            )
        }
    }

    @objc
    private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc
    private func sessionDidResignActive(_ notification: Notification) {
        eventTapSupervisor.setSessionActive(false)
    }

    @objc
    private func sessionDidBecomeActive(_ notification: Notification) {
        eventTapSupervisor.setSessionActive(true)
    }

    @objc
    private func systemDidWake(_ notification: Notification) {
        eventTapSupervisor.handleWakeFromSleep()
    }

    private func presentLearnedButtonAlert(_ buttonNumber: Int) {
        presentAlert(
            message: "Detected mouse button \(buttonNumber)",
            informativeText: "Button \(buttonNumber) is now available in Preferences. Change its action there if you want to remap it."
        )
    }

    private func presentAlert(message: String, informativeText: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
