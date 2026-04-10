import SwiftUI

@main
struct MagicMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible scenes — the app is menu-bar-only.
        // The AppDelegate manages the status item, menus, and preferences window.
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .defaultSize(width: 0, height: 0)
        .windowResizability(.contentSize)
    }
}
