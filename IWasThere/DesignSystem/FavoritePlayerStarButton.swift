import SwiftUI
import SwiftData

struct FavoritePlayerStarButton: View {
    let playerID: Int
    @Bindable var profile: UserProfile
    var playerName: String = ""
    var jerseyNumber: String = ""
    var teamID: Int = 0
    var league: League = .mlb
    var position: String = ""
    var onChange: (() -> Void)?

    private var isFavorite: Bool {
        profile.isFavoritePlayer(playerID)
    }

    var body: some View {
        Button {
            if isFavorite {
                profile.toggleFavoritePlayer(playerID)
            } else if !playerName.isEmpty {
                profile.toggleFavoritePlayer(
                    playerID,
                    meta: FavoritePlayerMeta(
                        playerID: playerID,
                        name: playerName,
                        jerseyNumber: jerseyNumber,
                        teamID: teamID,
                        league: league,
                        position: position
                    )
                )
            } else {
                profile.toggleFavoritePlayer(playerID)
            }
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
