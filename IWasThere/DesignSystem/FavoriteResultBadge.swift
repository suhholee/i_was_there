import SwiftUI

/// Green WIN / red LOSE when the favorite team played this game.
struct FavoriteResultBadge: View {
    let won: Bool?
    var compact: Bool = true

    var body: some View {
        switch won {
        case true:
            badge(text: "WIN", color: DesignTokens.winGreen)
        case false:
            badge(text: "LOSE", color: DesignTokens.loseRed)
        case nil:
            EmptyView()
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font((compact ? Font.caption : Font.subheadline).weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}
