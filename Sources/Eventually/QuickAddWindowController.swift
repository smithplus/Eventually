import AppKit
import SwiftUI

/// Hosts the QuickAddPanel in a floating, borderless NSPanel
/// that appears centered near the top of the active screen.
/// Holds the in-progress quick-add draft so it survives the window closing
/// (e.g. on click-outside) and is restored on reopen — Raycast-style.
@MainActor
final class QuickAddDraft: ObservableObject {
    @Published var name = ""
    @Published var dueDate: Date?
    @Published var listId: String?

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func clear() {
        name = ""
        dueDate = nil
        listId = nil
    }
}

@MainActor
final class QuickAddWindowController {
    private var panel: NSPanel?
    private let authService: AuthService
    private let tasksService: GoogleTasksService
    private let draft = QuickAddDraft()

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
            .environmentObject(draft)

        let hosting = NSHostingController(rootView: content)
        // Don't let the SwiftUI content drive the window size — the window owns
        // its size (otherwise the flexible/.infinity frames render blank).
        hosting.sizingOptions = []

        // Use the user's last-left frame if we have one, else a fresh size.
        let restored = restoredFrame()
        let size = restored?.size ?? initialSize()

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        hosting.view.autoresizingMask = [.width, .height]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.minSize = Self.minSize
        panel.maxSize = maxSize()
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let restored {
            panel.setFrame(restored, display: false)
        } else {
            positionPanel(panel, size: size)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Persist the frame whenever the user moves or resizes the window.
        observeFrameChanges(panel)

        // Close when clicking outside
        installClickOutsideMonitor()

        self.panel = panel
    }

    private static let minSize = NSSize(width: 460, height: 360)
    private static let screenMargin: CGFloat = 16

    private var screenFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Shrink a size so it always fits on the visible screen (with a margin).
    private func clampedToScreen(_ size: NSSize) -> NSSize {
        let vf = screenFrame
        return NSSize(width: min(size.width, vf.width - 2 * Self.screenMargin),
                      height: min(size.height, vf.height - 2 * Self.screenMargin))
    }

    /// Never taller/wider than the visible screen.
    private func maxSize() -> NSSize { clampedToScreen(NSSize(width: 1000, height: 4000)) }

    /// Initial size: a tall window (saved or default), capped to the screen.
    private func initialSize() -> NSSize { clampedToScreen(savedSize()) }

    func close() {
        removeClickOutsideMonitor()
        if let panel {
            saveFrame(panel.frame)
            removeFrameObservers()
        }
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Frame persistence (position + size, survives restarts)

    private func savedSize() -> NSSize {
        let d = UserDefaults.standard
        let w = d.double(forKey: DefaultsKey.panelWidth)
        let h = d.double(forKey: DefaultsKey.panelHeight)
        // Default to a tall window; clampedToScreen() caps it.
        guard w >= Self.minSize.width, h >= Self.minSize.height else {
            return NSSize(width: 560, height: 900)
        }
        return NSSize(width: w, height: h)
    }

    private func saveFrame(_ frame: NSRect) {
        let d = UserDefaults.standard
        d.set(frame.origin.x, forKey: DefaultsKey.panelX)
        d.set(frame.origin.y, forKey: DefaultsKey.panelY)
        d.set(frame.size.width, forKey: DefaultsKey.panelWidth)
        d.set(frame.size.height, forKey: DefaultsKey.panelHeight)
        d.set(true, forKey: DefaultsKey.panelHasSavedFrame)
    }

    /// The last frame the user left, if any — clamped to fit fully on screen.
    private func restoredFrame() -> NSRect? {
        let d = UserDefaults.standard
        guard d.bool(forKey: DefaultsKey.panelHasSavedFrame) else { return nil }
        let vf = screenFrame

        var rect = NSRect(origin: NSPoint(x: d.double(forKey: DefaultsKey.panelX),
                                          y: d.double(forKey: DefaultsKey.panelY)),
                          size: clampedToScreen(savedSize()))
        // Pull the origin back inside the visible area so it's never cut off.
        let m = Self.screenMargin
        rect.origin.x = min(max(rect.minX, vf.minX + m), vf.maxX - rect.width - m)
        rect.origin.y = min(max(rect.minY, vf.minY + m), vf.maxY - rect.height - m)
        return rect
    }

    // MARK: - Frame change observers

    private var frameObservers: [NSObjectProtocol] = []

    private func observeFrameChanges(_ panel: NSPanel) {
        let names: [NSNotification.Name] = [NSWindow.didMoveNotification, NSWindow.didResizeNotification]
        frameObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                self?.saveFrame(panel.frame)
            }
        }
    }

    private func removeFrameObservers() {
        frameObservers.forEach { NotificationCenter.default.removeObserver($0) }
        frameObservers = []
    }

    /// Position the panel per the user's preference (left/center/right),
    /// anchored near the top of the screen (Spotlight-style).
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let margin: CGFloat = 24
        let position = UserDefaults.standard.string(forKey: DefaultsKey.panelPosition) ?? "center"

        let x: CGFloat
        switch position {
        case "left":  x = frame.minX + margin
        case "right": x = frame.maxX - size.width - margin
        default:      x = frame.midX - size.width / 2
        }
        // Anchor the top edge near the top of the screen; clamp so it never
        // falls below the visible area for tall windows.
        let topGap: CGFloat = 16
        let y = max(frame.minY + margin, frame.maxY - size.height - topGap)
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
