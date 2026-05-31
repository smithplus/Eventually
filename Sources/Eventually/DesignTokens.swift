import SwiftUI

/// Eventually's design system.
/// Dark-mode-forward (matches the menu bar aesthetic), warm amber accent
/// to differentiate from Google Tasks' default blue.
enum Theme {

    // MARK: - Colors (semantic, adapt to light/dark)

    /// Primary accent — the system accent color (blue by default, like Google
    /// Tasks) so the app stays consistent with native macOS controls.
    static let accent = Color.accentColor
    static let accentSoft = Color.accentColor.opacity(0.15)

    /// Due-date accent (warm orange, distinct from the primary accent).
    static let dateChip = Color(hex: "E8954A")
    static let dateChipSoft = Color(hex: "E8954A").opacity(0.16)

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

// MARK: - Capsule button style

/// Filled, fully-rounded (pill) accent button — the app's primary action style.
struct CapsuleButton: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.spaceM)
            .padding(.vertical, 6)
            .background(Capsule().fill(enabled ? Theme.accent : Color.secondary.opacity(0.35)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
