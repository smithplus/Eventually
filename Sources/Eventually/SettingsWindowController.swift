import AppKit
import SwiftUI

/// Hosts the Settings UI in a regular titled window.
///
/// SwiftUI's `Settings` scene + the `showSettingsWindow:` selector is
/// unreliable for `LSUIElement` (menu bar) apps, so we manage the window
/// ourselves to guarantee it opens.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let authService: AuthService
    private let tasksService: GoogleTasksService
    private let shortcutManager: ShortcutManager

    init(authService: AuthService, tasksService: GoogleTasksService, shortcutManager: ShortcutManager) {
        self.authService = authService
        self.tasksService = tasksService
        self.shortcutManager = shortcutManager
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        // Reuse the existing window if already open.
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView()
            .environmentObject(authService)
            .environmentObject(tasksService)
            .environmentObject(shortcutManager)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Eventually Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Clear our reference when the user closes the window.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
        }

        self.window = window
    }
}
