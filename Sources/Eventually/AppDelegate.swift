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
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popoverView = PopoverView()
            .environmentObject(authService)
            .environmentObject(tasksService)
            .environmentObject(shortcutManager)

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 400, height: 640)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = NSHostingController(rootView: popoverView)
    }

    @objc func togglePopover(_ sender: AnyObject? = nil, focusAddTask: Bool = false) {
        guard let button = statusItem?.button else { return }

        if popover?.isShown == true {
            popover?.performClose(sender)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate the app so the transient popover reliably detects
            // outside clicks and dismisses itself.
            NSApp.activate(ignoringOtherApps: true)
            popover?.contentViewController?.view.window?.makeKey()

            if focusAddTask {
                NotificationCenter.default.post(name: .focusAddTask, object: nil)
            }
        }
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .openEventually) { [weak self] in
            self?.togglePopover(focusAddTask: false)
        }

        // ⌘⇧O opens the floating quick-add panel (requires sign-in)
        KeyboardShortcuts.onKeyUp(for: .openAndAddTask) { [weak self] in
            guard let self else { return }
            if self.authService.isAuthenticated {
                self.quickAdd.toggle()
            } else {
                self.togglePopover(focusAddTask: false)
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let focusAddTask = Notification.Name("focusAddTask")
    static let openSettings = Notification.Name("openSettings")
}

// MARK: - Appearance

/// Applies the user's appearance preference (system / light / dark) app-wide.
@MainActor
func applyAppearance() {
    let raw = UserDefaults.standard.string(forKey: DefaultsKey.appearance) ?? Appearance.system.rawValue
    NSApp.appearance = Appearance(rawValue: raw)?.nsAppearance
}
