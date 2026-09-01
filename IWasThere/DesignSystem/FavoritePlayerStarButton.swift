import SwiftUI
import SwiftData

struct FavoritePlayerStarButton: View {
    let playerID: Int
    @Bindable var profile: UserProfile
    var onChange: (() -> Void)?

    private var isFavorite: Bool {
        profile.isFavoritePlayer(playerID)
    }

    var body: some View {
        Button {
            profile.toggleFavoritePlayer(playerID)
            onChange?()
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.body.weight(.semibold))
                .foregroundStyle(isFavorite ? DesignTokens.favoriteStar : DesignTokens.secondaryText)
                .accessibilityLabel(isFavorite ? "Remove favorite player" : "Add favorite player")
        }
        .buttonStyle(.plain)
    }
}
