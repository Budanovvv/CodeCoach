import SwiftUI

/// One accent, used consistently. Everything else stays neutral so the panel
/// reads as a system surface rather than a competing UI.
enum Brand {
    static let accent = Color(red: 0.36, green: 0.55, blue: 0.98)
    static let accentWarm = Color(red: 0.98, green: 0.62, blue: 0.35)

    static let gradient = LinearGradient(
        colors: [accent, accentWarm],
        startPoint: .leading, endPoint: .trailing)

    /// Per-level tint: the badge colour is how the user tells at a glance how
    /// much of the answer they have already spent.
    static func tint(for level: HintLevel) -> Color {
        switch level {
        case .nudge: return accent
        case .approach: return Color(red: 0.55, green: 0.55, blue: 0.92)
        case .solution: return accentWarm
        }
    }
}
