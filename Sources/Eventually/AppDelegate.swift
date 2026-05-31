import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    let authService = AuthService()
    let tasksService = GoogleTasksService()
    let shortcutManager = ShortcutManager()
    private lazy var quickAdd = QuickAddWindowController(authService: authService, tasksService: tasksService)
    private lazy var settings = SettingsWindowController(authService: authService, tasksService: tasksService, shortcutManager: shortcutManager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        tasksService.authService = authService
        applyAppearance()
        setupMenuBar()
        setupGlobalShortcuts()

        NotificationCenter.default.addObserver(
            forName: .openSettings, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settings.show() }
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Eventually")
            button.image?.isTemplate = true
            button.action = #selector(openPrimary)
            button.target = self
        }

        // The popover now serves a single purpose: signing in. Once authed,
        // everything happens in the Command Window.
        let popoverView = PopoverView()
            .environmentObject(authService)
            .environmentObject(tasksService)
            .environmentObject(shortcutManager)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 360, height: 320)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: popoverView)
    }

    /// Single entry point: the Command Window when signed in, the login
    /// popover otherwise. Wired to the menu bar icon and the global shortcut.
    @objc func openPrimary() {
        if authService.isAuthenticated {
            quickAdd.toggle()
        } else {
            showLoginPopover()
        }
    }

    private func showLoginPopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .openCommandWindow) { [weak self] in
            self?.openPrimary()
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

// MARK: - Appearance

/// Applies the user's appearance preference (system / light / dark) app-wide.
@MainActor
func applyAppearance() {
    let raw = UserDefaults.standard.string(forKey: DefaultsKey.appearance) ?? Appearance.system.rawValue
    NSApp.appearance = Appearance(rawValue: raw)?.nsAppearance
}
