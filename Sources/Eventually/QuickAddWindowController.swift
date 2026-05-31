import AppKit
import SwiftUI

/// Hosts the QuickAddPanel in a floating, borderless NSPanel
/// that appears centered near the top of the active screen.
@MainActor
final class QuickAddWindowController {
    private var panel: NSPanel?
    private let authService: AuthService
    private let tasksService: GoogleTasksService

    init(authService: AuthService, tasksService: GoogleTasksService) {
        self.authService = authService
        self.tasksService = tasksService
    }

    func toggle() {
        if panel != nil {
            close()
        } else {
            show()
        }
    }

    func show() {
        // Make sure lists are loaded so the # selector works
        Task { await tasksService.fetchTaskLists() }

        let content = QuickAddPanel(onClose: { [weak self] in self?.close() })
            .environmentObject(authService)
            .environmentObject(tasksService)

        let hosting = NSHostingController(rootView: content)
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        positionPanel(panel, size: size)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Close when clicking outside
        installClickOutsideMonitor()

        self.panel = panel
    }

    func close() {
        removeClickOutsideMonitor()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Position the panel per the user's preference (center/left/right), vertically centered.
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let margin: CGFloat = 24
        let position = UserDefaults.standard.string(forKey: "panelPosition") ?? "center"

        let x: CGFloat
        switch position {
        case "left":  x = frame.minX + margin
        case "right": x = frame.maxX - size.width - margin
        default:      x = frame.midX - size.width / 2
        }
        let y = frame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Click outside to dismiss

    private var clickMonitor: Any?

    private func installClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}

/// A borderless panel that can still become key/main so its text fields
/// receive keyboard input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
