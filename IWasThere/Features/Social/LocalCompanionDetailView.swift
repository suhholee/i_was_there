import SwiftUI
import SwiftData

/// Detail for a diary companion who does not yet have a linked #iWasThere account.
struct LocalCompanionDetailView: View {
    let companionName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openGamesTogether) private var openGamesTogether
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var localProfiles: [UserProfile]

    @State private var usernameInput = ""
    @State private var isLinking = false
    @State private var linkError: String?
    @State private var linkedProfile: PublicUserProfile?
    @State private var didLink = false

    private var togetherGames: [AttendedGame] {
        GameLogFilter.gamesTogether(withLocalCompanionName: companionName, in: allGames)
    }

    private var attendance: LeaderboardEngine.AttendanceRecord {
        let profile = localProfiles.first
        return LeaderboardEngine.favoriteAttendanceTogether(
            games: togetherGames,
            mlbFavoriteTeamID: profile?.favoriteTeamID,
            kboFavoriteTeamID: profile?.favoriteKBOTeamID
        )
    }

    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    gamesTogetherCard
                    if didLink, let linkedProfile {
                        linkedSuccess(linkedProfile)
                    } else {
                        linkSection
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(companionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DesignTokens.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 12) {
            ProfileAvatarView(image: nil, diameter: 96)
            Text(companionName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText)
            Text("No account linked yet")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var gamesTogetherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Games together")
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(
                        togetherGames.count == 1
                            ? "1 game attended together"
                            : "\(togetherGames.count) games attended together"
                    )
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
                    Spacer()
                    if togetherGames.count > 0 {
                        Button("View in Games") {
                            openGamesTogether?(
                                GameFriendFilterOption(
                                    id: "name:\(companionName.lowercased())",
                                    chipLabel: companionName,
                                    linkedUserId: nil,
                                    matchName: companionName
                                )
                            )
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }

                if attendance.games > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(attendance.recordLabel)
                            .font(ScaledTypography.record)
                            .foregroundStyle(DesignTokens.primaryText)
                            .monospacedDigit()
                        Text(attendance.winPercentageLabel)
                            .font(ScaledTypography.recordPct)
                            .foregroundStyle(DesignTokens.accent)
                            .monospacedDigit()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var linkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link to an account")
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            Text("When they create an account, enter their @username here. Their name will update to the one they chose on their profile.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)

            HStack(spacing: 8) {
                TextField("@username", text: $usernameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(DesignTokens.surface)
                    .foregroundStyle(DesignTokens.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    Task { await linkAccount() }
                } label: {
                    if isLinking {
                        ProgressView()
                            .frame(width: 64, height: 20)
                    } else {
                        Text("Link")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(DesignTokens.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(DesignTokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(isLinking || normalizedUsername.isEmpty)
            }

            if let linkError {
                Text(linkError)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.loseRed)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func linkedSuccess(_ profile: PublicUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Linked")
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)
            Text("Updated to \(profile.displayName.isEmpty ? profile.usernameTag : profile.displayName). Open their profile to follow or view games.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)

            NavigationLink {
                UserProfileView(userId: profile.userId)
            } label: {
                Text("View profile")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(DesignTokens.accent.opacity(0.2))
                    .foregroundStyle(DesignTokens.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var normalizedUsername: String {
        UsernameRules.normalize(usernameInput)
    }

    @MainActor
    private func linkAccount() async {
        let username = normalizedUsername
        guard !username.isEmpty else { return }

        isLinking = true
        linkError = nil
        defer { isLinking = false }

        do {
            guard let profile = try await SocialProfileService.shared.fetchProfile(username: username) else {
                linkError = "No account found for @\(username)."
                return
            }
            if profile.userId == AuthSession.shared.userId {
                linkError = "That’s your own account."
                return
            }

            let touched = GameFriendStore.linkLocalCompanion(
                named: companionName,
                to: profile,
                across: allGames,
                modelContext: modelContext
            )
            guard touched > 0 else {
                linkError = "Couldn’t find games tagged with \(companionName)."
                return
            }

            for game in GameLogFilter.gamesTogether(with: UserSearchResult(profile: profile), in: allGames) {
                CloudSyncTrigger.game(game, modelContext: modelContext)
            }

            linkedProfile = profile
            didLink = true
            usernameInput = ""
        } catch {
            linkError = error.localizedDescription
        }
    }
}
