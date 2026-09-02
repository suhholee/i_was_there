import SwiftData
import SwiftUI
import UIKit

struct UserProfileView: View {
    let userId: UUID

    @Environment(\.openGamesTogether) private var openGamesTogether
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var localProfiles: [UserProfile]
    @State private var profile: PublicUserProfile?
    @State private var games: [AttendedGame] = []
    @State private var gameContainer: ModelContainer?
    @State private var avatarImage: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowActionLoading = false
    @State private var showUnfollowConfirmation = false
    @State private var enrichedPlayerPositions: [Int: String] = [:]
    @State private var gamesLeagueFilter: League = .mlb

    private var filteredProfileGames: [AttendedGame] {
        games
            .filter { $0.resolvedLeague == gamesLeagueFilter }
            .sorted { $0.gameDate > $1.gameDate }
    }

    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()

            if isLoading && profile == nil {
                ProgressView()
            } else if let errorMessage, profile == nil {
                ContentUnavailableView(
                    "Profile unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(errorMessage)
                )
            } else if let profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(profile)
                        followSection(profile)
                        if profile.relationship == .mutual {
                            gamesTogetherSection(profile)
                        }
                        favoritePlayersSection(profile)
                        gamesSection(profile)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(profile?.displayName.isEmpty == false ? profile!.displayName : "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DesignTokens.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: userId) {
            enrichedPlayerPositions = [:]
            await loadProfile(forceRefresh: true)
        }
        .refreshable {
            await loadProfile(forceRefresh: true, silent: true)
        }
        .onAppear {
            guard profile != nil else { return }
            Task { await loadProfile(forceRefresh: true, silent: true) }
        }
        .alert("Unfollow @\(profile?.username ?? "")?", isPresented: $showUnfollowConfirmation) {
            Button("Unfollow", role: .destructive) {
                Task { await unfollow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will no longer be mutual followers.")
        }
    }

    @ViewBuilder
    private func followSection(_ profile: PublicUserProfile) -> some View {
        FollowActionButton(
            status: profile.relationship,
            isLoading: isFollowActionLoading,
            onFollow: { Task { await requestFollow() } },
            onCancelRequest: { Task { await cancelRequest() } },
            onAccept: { Task { await acceptRequest() } },
            onDecline: { Task { await declineRequest() } },
            onUnfollow: { showUnfollowConfirmation = true }
        )
    }

    @ViewBuilder
    private func header(_ profile: PublicUserProfile) -> some View {
        VStack(spacing: 12) {
            RemoteProfileAvatarView(storagePath: profile.avatarStoragePath, image: $avatarImage, diameter: 96)

            Text(profile.displayName.isEmpty ? profile.usernameTag : profile.displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText)

            if !profile.displayName.isEmpty {
                Text(profile.usernameTag)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            }

            favoriteTeamsLogos(profile)

            if profile.visibility == .private {
                Label("Private account", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func gamesTogetherSection(_ profile: PublicUserProfile) -> some View {
        let friend = UserSearchResult(profile: profile)
        let togetherGames = GameLogFilter.gamesTogether(with: friend, in: allGames)
        let count = togetherGames.count
        let localProfile = localProfiles.first
        let attendance = LeaderboardEngine.favoriteAttendanceTogether(
            games: togetherGames,
            mlbFavoriteTeamID: localProfile?.favoriteTeamID,
            kboFavoriteTeamID: localProfile?.favoriteKBOTeamID
        )

        VStack(alignment: .leading, spacing: 12) {
            Text("Games together")
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(count == 1 ? "1 game attended together" : "\(count) games attended together")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                    Spacer()
                    if count > 0 {
                        Button("View in Games") {
                            openGamesTogether?(friend)
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
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(attendance.winPercentageLabel)
                            .font(ScaledTypography.recordPct)
                            .foregroundStyle(DesignTokens.accent)
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private func favoritePlayersSection(_ profile: PublicUserProfile) -> some View {
        let metaByID = profile.favoritePlayerMetaByID()
        let players = profile.favoritePlayerIds.compactMap { metaByID[$0] }

        if !players.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Favorite players")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)

                ForEach(players, id: \.playerID) { meta in
                    let league = League(rawValue: meta.league) ?? profile.league
                    NavigationLink {
                        PlayerDetailView(
                            playerID: meta.playerID,
                            playerName: meta.name,
                            jerseyNumber: meta.jerseyNumber,
                            teamID: meta.teamID,
                            prefersPitching: false,
                            league: league
                        )
                    } label: {
                        JerseyCardView(
                            number: meta.jerseyNumber,
                            name: meta.name,
                            subtitle: "Favorite",
                            valueLabel: favoritePlayerPositionLabel(for: meta),
                            theme: TeamTheme.forTeamID(meta.teamID),
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func gamesSection(_ profile: PublicUserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Games")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)
                Spacer(minLength: 8)
                if profile.canViewGames {
                    gamesLeagueMenu
                }
            }

            if !profile.canViewGames {
                Text("This account is private. Games are only visible to mutual followers.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if games.isEmpty {
                Text("No games logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else if filteredProfileGames.isEmpty {
                Text("No \(gamesLeagueFilter.title) games logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else if let gameContainer {
                ForEach(filteredProfileGames) { game in
                    NavigationLink {
                        GameDetailView(
                            game: game,
                            isReadOnly: true,
                            favoriteTeamIDOverride: profile.favoriteTeamID(for: game.resolvedLeague)
                        )
                        .modelContainer(gameContainer)
                    } label: {
                        remoteGameCard(game, favoriteTeamID: profile.favoriteTeamID(for: game.resolvedLeague))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var gamesLeagueMenu: some View {
        Menu {
            ForEach(League.allCases) { league in
                Button {
                    gamesLeagueFilter = league
                } label: {
                    if league == gamesLeagueFilter {
                        Label(league.title, systemImage: "checkmark")
                    } else {
                        Text(league.title)
                    }
                }
            }
        } label: {
            DropdownMenuLabel(title: gamesLeagueFilter.title, style: .compact)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DesignTokens.surface)
                .clipShape(Capsule())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func remoteGameCard(_ game: AttendedGame, favoriteTeamID: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("\(game.awayTeamName) @ \(game.homeTeamName)")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.cardPrimaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                FavoriteResultBadge(won: game.favoriteTeamWon(favoriteTeamID: favoriteTeamID))
            }
            Text("\(game.awayScore)–\(game.homeScore) · \(game.gameCardDateLabel)")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.cardSecondaryText)
                .monospacedDigit()
            Text(game.startersLabel)
                .font(.caption)
                .foregroundStyle(DesignTokens.cardSecondaryText)
            if !game.eventTitle.isEmpty {
                Text(game.eventTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
            }
            if !game.friendsLabel.isEmpty {
                Text("w/ \(game.friendsLabel)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func favoritePlayerPositionLabel(for meta: FavoritePlayerMeta) -> String {
        if let enriched = enrichedPlayerPositions[meta.playerID],
           !enriched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return enriched
        }
        return meta.jerseyValueLabel
    }

    @MainActor
    private func enrichFavoritePlayerPositions(for profile: PublicUserProfile) async {
        let metaByID = profile.favoritePlayerMetaByID()
        let missingIDs = profile.favoritePlayerIds.filter { playerID in
            let stored = metaByID[playerID]?.position.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty
        }
        guard !missingIDs.isEmpty else {
            enrichedPlayerPositions = [:]
            return
        }

        let candidates = await FavoritePlayerCatalog.loadCandidates(
            mlbTeamID: profile.favoriteTeamId,
            kboTeamID: profile.favoriteKboTeamId
        )
        var positions: [Int: String] = [:]
        for playerID in missingIDs {
            guard let position = candidates.first(where: { $0.playerID == playerID })?.position,
                  !position.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            positions[playerID] = position
        }
        enrichedPlayerPositions = positions
    }

    @MainActor
    private func loadProfile(forceRefresh: Bool = false, silent: Bool = false) async {
        if !silent {
            isLoading = true
        }
        errorMessage = nil
        if forceRefresh {
            avatarImage = nil
            enrichedPlayerPositions = [:]
        }
        if !silent {
            games = []
            gameContainer = nil
            gamesLeagueFilter = .mlb
        }
        defer {
            if !silent {
                isLoading = false
            }
        }

        do {
            guard let loaded = try await SocialProfileService.shared.fetchProfile(userId: userId) else {
                errorMessage = "This profile could not be found."
                profile = nil
                games = []
                gameContainer = nil
                avatarImage = nil
                return
            }
            profile = loaded
            gamesLeagueFilter = loaded.league
            avatarImage = await SocialProfileService.shared.downloadAvatar(
                path: loaded.avatarStoragePath,
                forceRefresh: forceRefresh
            )
            await enrichFavoritePlayerPositions(for: loaded)
            try await loadGamesIfNeeded(for: loaded, forceRefresh: forceRefresh)
        } catch {
            if !silent {
                profile = nil
                games = []
                gameContainer = nil
                avatarImage = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadGamesIfNeeded(for loaded: PublicUserProfile, forceRefresh: Bool = false) async throws {
        guard loaded.canViewGames else {
            games = []
            gameContainer = nil
            return
        }

        if forceRefresh {
            gameContainer = nil
        }

        let container: ModelContainer
        if let gameContainer {
            container = gameContainer
        } else {
            container = try EphemeralModelContainer.make()
            gameContainer = container
        }
        let context = ModelContext(container)
        games = try await SocialProfileService.shared.loadVisibleGames(
            for: loaded,
            modelContext: context
        )
    }

    @MainActor
    private func requestFollow() async {
        isFollowActionLoading = true
        defer { isFollowActionLoading = false }
        do {
            _ = try await FollowService.shared.requestFollow(targetUserId: userId)
            await loadProfile(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func acceptRequest() async {
        isFollowActionLoading = true
        defer { isFollowActionLoading = false }
        do {
            try await FollowService.shared.acceptFollow(from: userId)
            await loadProfile(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func declineRequest() async {
        isFollowActionLoading = true
        defer { isFollowActionLoading = false }
        do {
            try await FollowService.shared.declineFollow(from: userId)
            await loadProfile(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func cancelRequest() async {
        isFollowActionLoading = true
        defer { isFollowActionLoading = false }
        do {
            try await FollowService.shared.cancelFollowRequest(targetUserId: userId)
            await loadProfile(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func unfollow() async {
        isFollowActionLoading = true
        defer { isFollowActionLoading = false }
        do {
            try await FollowService.shared.unfollow(targetUserId: userId)
            await loadProfile(forceRefresh: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func favoriteTeamsLogos(_ profile: PublicUserProfile) -> some View {
        let hasMLB = profile.favoriteTeamId != nil
            && !(profile.favoriteTeamAbbr ?? "").isEmpty
        let hasKBO = profile.favoriteKboTeamId != nil
            && !(profile.favoriteKboTeamAbbr ?? "").isEmpty

        if hasMLB || hasKBO {
            HStack(spacing: 12) {
                if hasMLB, let mlbID = profile.favoriteTeamId {
                    TeamLogoImage(teamID: mlbID, size: 28)
                }
                if hasKBO, let kboID = profile.favoriteKboTeamId {
                    TeamLogoImage(teamID: kboID, size: 28)
                }
            }
        }
    }
}

struct RemoteProfileAvatarView: View {
    let storagePath: String?
    @Binding var image: UIImage?
    var diameter: CGFloat = 96

    var body: some View {
        ProfileAvatarView(image: image, diameter: diameter)
    }
}
