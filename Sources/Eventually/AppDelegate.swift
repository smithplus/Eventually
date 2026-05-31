import AppKit
import SwiftUI
import KeyboardShortcuts
import Network

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?

    let authService = AuthService()
    let tasksService = GoogleTasksService()
    let shortcutManager = ShortcutManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalShortcuts()
        tasksService.authService = authService
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
        popover?.contentSize = NSSize(width: 360, height: 500)
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

        KeyboardShortcuts.onKeyUp(for: .openAndAddTask) { [weak self] in
            self?.togglePopover(focusAddTask: true)
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let focusAddTask = Notification.Name("focusAddTask")
}
