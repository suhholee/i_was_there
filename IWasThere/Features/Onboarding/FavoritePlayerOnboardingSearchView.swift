import SwiftUI
import SwiftData

struct FavoritePlayerOnboardingSearchView: View {
    @Bindable var profile: UserProfile
    let mlbTeamID: Int
    let kboTeamID: Int

    @State private var query = ""
    @State private var candidates: [RosterPlayerCandidate] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCandidates: [RosterPlayerCandidate] {
        guard !trimmedQuery.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.jerseyNumber.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.position.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search players on your favorite teams")
                        .font(.body)
                        .foregroundStyle(DesignTokens.secondaryText.opacity(0.85))
                        .allowsHitTesting(false)
                }
                TextField("", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .font(.body)
            .foregroundStyle(DesignTokens.primaryText)
            .tint(DesignTokens.primaryText)
            .padding(12)
            .background(DesignTokens.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                }
                .padding(.vertical, 24)
            } else if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.accent)
            } else if candidates.isEmpty {
                Text("Pick a favorite team first, or skip for now.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else if filteredCandidates.isEmpty {
                Text("No players match \"\(query)\".")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCandidates) { player in
                            playerRow(player)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }

            if !profile.favoritePlayerIDs.isEmpty {
                Text("\(profile.favoritePlayerIDs.count) favorite\(profile.favoritePlayerIDs.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
            }
        }
        .task(id: "\(mlbTeamID)-\(kboTeamID)") {
            await loadCandidates()
        }
    }

    private func playerRow(_ player: RosterPlayerCandidate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(2)
                Text("\(player.league.title) · \(player.position.isEmpty ? "Player" : player.position)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
            }
            Spacer(minLength: 8)
            FavoritePlayerStarButton(playerID: player.playerID, profile: profile)
        }
        .padding(12)
        .background(DesignTokens.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func loadCandidates() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let mlbID = mlbTeamID > 0 ? mlbTeamID : nil
        let kboID = kboTeamID > 0 ? kboTeamID : nil
        let rows = await FavoritePlayerCatalog.loadCandidates(mlbTeamID: mlbID, kboTeamID: kboID)
        candidates = rows
        if rows.isEmpty, mlbID == nil, kboID == nil {
            loadError = nil
        }
    }
}
