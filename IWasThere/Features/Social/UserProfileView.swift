import SwiftData
import SwiftUI
import UIKit

struct UserProfileView: View {
    let userId: UUID

    @Environment(\.openGamesTogether) private var openGamesTogether
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var localProfiles: [UserProfile]
    @State private var profile: PublicUserProfile?
    @State private var gameSummaries: [RemoteGameSummary] = []
    @State private var avatarImage: UIImage?
    @State private var isLoading = true
    @State private var isLoadingGames = false
    @State private var errorMessage: String?
    @State private var isFollowActionLoading = false
    @State private var showUnfollowConfirmation = false
    @State private var enrichedPlayerPositions: [Int: String] = [:]
    @State private var gamesLeagueFilter: League = .mlb

    private var filteredProfileGames: [RemoteGameSummary] {
        gameSummaries
            .filter { $0.resolvedLeague == gamesLeagueFilter }
            .sorted { $0.row.gameDate > $1.row.gameDate }
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
                            openGamesTogether?(GameFriendFilterOption(friend: friend))
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
            } else if isLoadingGames && gameSummaries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if gameSummaries.isEmpty {
                Text("No games logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else if filteredProfileGames.isEmpty {
                Text("No \(gamesLeagueFilter.title) games logged yet.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                ForEach(filteredProfileGames) { summary in
                    NavigationLink {
                        RemoteGameDetailLoader(
                            summary: summary,
                            favoriteTeamID: profile.favoriteTeamID(for: summary.resolvedLeague)
                        )
                    } label: {
                        remoteGameCard(summary, favoriteTeamID: profile.favoriteTeamID(for: summary.resolvedLeague))
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

    private func remoteGameCard(_ summary: RemoteGameSummary, favoriteTeamID: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(summary.matchupLabel)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.cardPrimaryText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                FavoriteResultBadge(outcome: summary.favoriteTeamResult(favoriteTeamID: favoriteTeamID))
            }
            if let score = summary.scoreLabel {
                Text("\(score) · \(summary.dateLabel)")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
                    .monospacedDigit()
            } else {
                Text(summary.dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            if !summary.startersLabel.isEmpty {
                Text(summary.startersLabel)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            if !summary.row.eventTitle.isEmpty {
                Text(summary.row.eventTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
            }
            if !summary.friendsLabel.isEmpty {
                Text("w/ \(summary.friendsLabel)")
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
            gameSummaries = []
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
                gameSummaries = []
                avatarImage = nil
                return
            }
            profile = loaded
            gamesLeagueFilter = loaded.league
            if !silent {
                isLoading = false
            }

            async let avatarTask = SocialProfileService.shared.downloadAvatar(
                path: loaded.avatarStoragePath,
                forceRefresh: forceRefresh
            )
            async let positionsTask: Void = enrichFavoritePlayerPositions(for: loaded)
            async let gamesTask: Void = loadGamesIfNeeded(for: loaded, forceRefresh: forceRefresh)

            avatarImage = await avatarTask
            await positionsTask
            try await gamesTask
        } catch {
            if !silent {
                profile = nil
                gameSummaries = []
                avatarImage = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadGamesIfNeeded(for loaded: PublicUserProfile, forceRefresh: Bool = false) async throws {
        guard loaded.canViewGames else {
            gameSummaries = []
            return
        }

        if !forceRefresh, !gameSummaries.isEmpty {
            return
        }

        isLoadingGames = true
        do {
            // 1) Paint games (+ scores/starters from Supabase) as soon as rows arrive.
            var summaries = try await SocialProfileService.shared.loadVisibleGameSummaries(for: loaded)
            gameSummaries = summaries
            isLoadingGames = false

            // 2) Friend names + hybrid fill-in only for rows still missing a snapshot.
            async let withFriends = SocialProfileService.shared.attachFriendNames(
                to: summaries,
                profileUserId: loaded.userId
            )
            async let enriched = SocialProfileService.shared.enrichMissingDisplaySnapshots(summaries)

            let friendsAttached = await withFriends
            let snapshotFilled = await enriched

            guard !Task.isCancelled else { return }

            // Merge: prefer enriched display fields, keep friend names from attach step.
            let enrichedById = Dictionary(uniqueKeysWithValues: snapshotFilled.map { ($0.id, $0) })
            summaries = friendsAttached.map { summary in
                guard let filled = enrichedById[summary.id] else { return summary }
                return RemoteGameSummary(
                    id: summary.id,
                    row: filled.row,
                    friendNames: summary.friendNames
                )
            }
            gameSummaries = summaries
        } catch {
            isLoadingGames = false
            throw error
        }
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

/// Hydrates one remote game on demand when opened from a People profile.
struct RemoteGameDetailLoader: View {
    let summary: RemoteGameSummary
    let favoriteTeamID: Int?

    @State private var container: ModelContainer?
    @State private var game: AttendedGame?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()

            if let game, let container {
                GameDetailView(
                    game: game,
                    isReadOnly: true,
                    favoriteTeamIDOverride: favoriteTeamID
                )
                .modelContainer(container)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load game",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading game…")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: summary.id) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let container = try EphemeralModelContainer.make()
            let context = ModelContext(container)
            let hydrated = try await SocialProfileService.shared.loadVisibleGameDetail(
                summary: summary,
                modelContext: context
            )
            self.container = container
            self.game = hydrated
        } catch {
            errorMessage = error.localizedDescription
            game = nil
            container = nil
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
