import SwiftUI

@main
struct EventuallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.authService)
                .environmentObject(appDelegate.tasksService)
                .environmentObject(appDelegate.shortcutManager)
        }
    }
}
