import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// The single global shortcut: opens the Command Window (⌘⇧O by default).
    static let openCommandWindow = Self("openAndAddTask", default: .init(.o, modifiers: [.command, .shift]))
}

class ShortcutManager: ObservableObject {
    // Shortcuts are managed via KeyboardShortcuts package
    // Users can customize them in Settings
}
