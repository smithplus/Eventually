import AppKit

/// Centralized UserDefaults keys, so the same string isn't retyped across files.
enum DefaultsKey {
    static let appearance = "appearance"
    static let panelPosition = "panelPosition"
    static let defaultCommandView = "defaultCommandView"
    static let lastCommandView = "lastCommandView"
    static let panelHasSavedFrame = "panelHasSavedFrame"
    static let panelX = "panelX"
    static let panelY = "panelY"
    static let panelWidth = "panelWidth"
    static let panelHeight = "panelHeight"
    static let launchAtLogin = "launchAtLogin"
    static let showBadgeCount = "showBadgeCount"
    static let groupByList = "groupByList"
}

/// App appearance preference, shared by the Settings picker and the applier.
enum Appearance: String, CaseIterable {
    case system, light, dark

    var label: String { rawValue.capitalized }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil   // follow the system
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}
