import AppKit
import SwiftUI
import KeyboardShortcuts
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    let authService = AuthService()
    let tasksService = GoogleTasksService()
    let shortcutManager = ShortcutManager()
    private lazy var quickAdd = QuickAddWindowController(authService: authService, tasksService: tasksService)
    private lazy var settings = SettingsWindowController(authService: authService, tasksService: tasksService, shortcutManager: shortcutManager)
    private var cancellables = Set<AnyCancellable>()

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

        // Keep the menu bar badge in sync with the task data and the setting.
        tasksService.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateBadge() }
            .store(in: &cancellables)

        // Clear cached tasks when the user signs out so nothing stale lingers.
        authService.$isAuthenticated
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] signedIn in
                if !signedIn { self?.tasksService.clearCache() }
                self?.updateBadge()
            }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: .badgeSettingChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateBadge() }
        }
        NotificationCenter.default.addObserver(
            forName: .autoRefreshChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setupAutoRefresh() }
        }
        setupAutoRefresh()
    }

    private var refreshTimer: Timer?

    /// Periodically refresh while signed in, per the Settings interval (0 = off).
    private func setupAutoRefresh() {
        refreshTimer?.invalidate()
        // Read as integer; default to 15 if unset (object==nil) or 0 → off.
        let stored = UserDefaults.standard.object(forKey: DefaultsKey.autoRefreshMinutes)
        let minutes = stored == nil ? 15 : UserDefaults.standard.integer(forKey: DefaultsKey.autoRefreshMinutes)
        guard minutes > 0 else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.authService.isAuthenticated else { return }
                await self.tasksService.fetchTaskLists()
            }
        }
    }

    /// Show today's task count (overdue + due today) next to the icon, if enabled.
    private func updateBadge() {
        guard let button = statusItem?.button else { return }
        let enabled = UserDefaults.standard.object(forKey: DefaultsKey.showBadgeCount) as? Bool ?? true
        let count = authService.isAuthenticated ? tasksService.rows(for: .today).count : 0
        button.title = (enabled && count > 0) ? " \(count)" : ""
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        NotificationCenter.default.addObserver(
            forName: .menuBarIconSettingChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshMenuBarIcon() }
        }
        refreshMenuBarIcon()
    }

    /// Show or hide the status item per the Settings toggle. Hidden by choice
    /// still leaves the global shortcut (⌘⇧O) working.
    private func refreshMenuBarIcon() {
        let show = UserDefaults.standard.object(forKey: DefaultsKey.showMenuBarIcon) as? Bool ?? true
        if show, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Eventually")
            item.button?.image?.isTemplate = true
            item.button?.action = #selector(openPrimary)
            item.button?.target = self
            statusItem = item
            updateBadge()
        } else if !show, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Single entry point — the Command Window (which itself shows login when
    /// signed out). Wired to the menu bar icon and the global shortcut.
    @objc func openPrimary() {
        quickAdd.toggle()
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
    static let badgeSettingChanged = Notification.Name("badgeSettingChanged")
    static let autoRefreshChanged = Notification.Name("autoRefreshChanged")
    static let menuBarIconSettingChanged = Notification.Name("menuBarIconSettingChanged")
}

// MARK: - Appearance

/// Applies the user's appearance preference (system / light / dark) app-wide.
@MainActor
func applyAppearance() {
    let raw = UserDefaults.standard.string(forKey: DefaultsKey.appearance) ?? Appearance.system.rawValue
    NSApp.appearance = Appearance(rawValue: raw)?.nsAppearance
}
