import SwiftUI

/// Eventually's design system.
/// Dark-mode-forward (matches the menu bar aesthetic), warm amber accent
/// to differentiate from Google Tasks' default blue.
enum Theme {

    // MARK: - Colors (semantic, adapt to light/dark)

    /// Warm amber — the brand accent. "Eventually, in good time."
    static let accent = Color(hex: "F0A830")
    static let accentSoft = Color(hex: "F0A830").opacity(0.16)

    /// Date chips (calm blue-green, distinct from accent)
    static let dateChip = Color(hex: "5BB8A5")
    static let dateChipSoft = Color(hex: "5BB8A5").opacity(0.16)

    /// Overdue / urgent
    static let danger = Color(hex: "E5604D")

    // MARK: - Spacing (8pt grid)

    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 16
    static let spaceL: CGFloat = 24
    static let spaceXL: CGFloat = 32

    // MARK: - Radius

    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 16
}

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}
