import SwiftUI

@main
struct MagicMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: AppModel.shared)
        }
    }
}
