import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let openEventually = Self("openEventually", default: .init(.t, modifiers: [.command, .shift]))
    static let openAndAddTask = Self("openAndAddTask", default: .init(.o, modifiers: [.command, .shift]))
}

class ShortcutManager: ObservableObject {
    // Shortcuts are managed via KeyboardShortcuts package
    // Users can customize them in Settings
}
