import SwiftUI

enum DesignTokens {
    /// Stadium-night page background.
    static let background = Color(red: 0.07, green: 0.09, blue: 0.12)
    /// Slightly lifted dark surface (controls on dark pages).
    static let surface = Color(red: 0.12, green: 0.15, blue: 0.20)
    /// White cards for game rows / player lines.
    static let cardBackground = Color.white
    /// Fixed brand red for event nights / diary accents (not team-dependent).
    static let accent = Color(red: 0.85, green: 0.18, blue: 0.22)
    /// Sign-in CTA on auth screen (distinct from create-account red).
    static let authSignInBlue = Color(red: 0.20, green: 0.48, blue: 0.95)
    static let favoriteStar = Color(red: 1.0, green: 0.82, blue: 0.20)
    static let winGreen = Color(red: 0.12, green: 0.62, blue: 0.32)
    static let loseRed = Color(red: 0.82, green: 0.16, blue: 0.20)
    /// Text on dark page background.
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    /// Text on white cards.
    static let cardPrimaryText = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let cardSecondaryText = Color(red: 0.35, green: 0.38, blue: 0.42)
}
