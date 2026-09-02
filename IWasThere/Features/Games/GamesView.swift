import SwiftUI
import SwiftData

struct GamesView: View {
    @Binding var externalFriendFilter: GameFriendFilterOption?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.teamTheme) private var teamTheme
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var showingAddGame = false
    /// `0` = all seasons
    @State private var seasonFilter: Int = 0
    /// `0` = all teams
    @State private var filterTeamID: Int = 0
    @State private var gamePhaseFilter: GamePhaseFilter = .all
    @State private var venueFilter: String = ""
    @State private var favoriteResultFilter: FavoriteResultFilter = .all
    @State private var friendFilter: GameFriendFilterOption = .anyone
    @State private var mutualFriends: [UserSearchResult] = []

    private var activeLeague: League { profiles.first?.league ?? .mlb }
    private var favoriteTeamID: Int? { profiles.first?.favoriteTeamID(for: activeLeague) }

    private var games: [AttendedGame] {
        allGames.filter { $0.resolvedLeague == activeLeague }
    }

    private var seasonsInLog: [Int] {
        GameLogFilter.seasons(in: games)
    }

    private var teamsInLog: [GameFilterTeam] {
        GameLogFilter.teams(in: games, league: activeLeague, favoriteTeamID: favoriteTeamID)
    }

    private var venuesInLog: [String] {
        GameLogFilter.venues(in: games)
    }

    private var friendFilterOptions: [GameFriendFilterOption] {
        GameLogFilter.friendFilterOptions(mutualFriends: mutualFriends, games: games)
    }

    private var filteredGames: [AttendedGame] {
        GameLogFilter.apply(
            to: games,
            season: seasonFilter == 0 ? nil : seasonFilter,
            teamID: filterTeamID == 0 ? nil : filterTeamID,
            phase: gamePhaseFilter,
            venue: venueFilter.isEmpty ? nil : venueFilter,
            favoriteResult: favoriteResultFilter,
            favoriteTeamID: favoriteTeamID,
            friend: friendFilter.isActive ? friendFilter : nil
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No \(activeLeague.title) games yet", systemImage: "baseball.diamond.bases")
                    } description: {
                        Text("Log a game to your iWasThere Diary!")
                            .foregroundStyle(DesignTokens.secondaryText)
                    } actions: {
                        Button("Add game") { showingAddGame = true }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.accent)
                            .foregroundStyle(.white)
                    }
                    .foregroundStyle(DesignTokens.primaryText)
                } else {
                    VStack(spacing: 0) {
                        GameAttendanceFiltersBar(
                            seasonFilter: $seasonFilter,
                            teamFilter: $filterTeamID,
                            gamePhaseFilter: $gamePhaseFilter,
                            venueFilter: $venueFilter,
                            favoriteResultFilter: $favoriteResultFilter,
                            friendFilter: $friendFilter,
                            seasonsInLog: seasonsInLog,
                            teamsInLog: teamsInLog,
                            venuesInLog: venuesInLog,
                            friendFilterOptions: friendFilterOptions,
                            favoriteTeamID: favoriteTeamID
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        if filteredGames.isEmpty {
                            ContentUnavailableView(
                                "No games match",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try another year, team, stadium, or filter.")
                            )
                            .foregroundStyle(DesignTokens.primaryText)
                            .frame(maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(filteredGames) { game in
                                        NavigationLink {
                                            GameDetailView(game: game)
                                        } label: {
                                            gameCard(game)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(activeLeague.title) Games")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DesignTokens.primaryText)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddGame = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.primaryText)
                }
            }
            .sheet(isPresented: $showingAddGame) {
                AddGameView(league: activeLeague)
                    .environment(\.modelContext, modelContext)
            }
            .onChange(of: activeLeague) { _, _ in
                resetFilters()
            }
            .task(id: AuthSession.shared.isAuthenticated) {
                await loadMutualFriends()
            }
            .onChange(of: externalFriendFilter) { _, newValue in
                guard let newValue else { return }
                friendFilter = newValue
                externalFriendFilter = nil
            }
            .task(id: games.map(\.mlbGamePk)) {
                try? await Task.sleep(for: .milliseconds(300))
                for game in games {
                    await StarterBackfill.ensureStarters(for: game, modelContext: modelContext)
                    await Task.yield()
                }
            }
        }
    }

    private func resetFilters() {
        seasonFilter = 0
        filterTeamID = 0
        gamePhaseFilter = .all
        venueFilter = ""
        favoriteResultFilter = .all
        friendFilter = .anyone
    }

    @MainActor
    private func loadMutualFriends() async {
        guard AuthSession.shared.isAuthenticated else {
            mutualFriends = []
            return
        }
        do {
            mutualFriends = try await FollowService.shared.listMutualFollows()
        } catch {
            mutualFriends = []
        }
    }

    private func gameCard(_ game: AttendedGame) -> some View {
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
                .minimumScaleFactor(0.85)
                .lineLimit(1)
            Text(game.startersLabel)
                .font(.caption)
                .foregroundStyle(DesignTokens.cardSecondaryText)
            if let phase = game.gamePhaseShortLabel {
                Text(phase)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            if !game.resolvedVenueName.isEmpty {
                Text(game.resolvedVenueName)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
                    .lineLimit(1)
            }
            if let attendance = game.attendanceLabel {
                Text(attendance)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            if !game.eventTitle.isEmpty {
                Text(game.eventTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
                    .lineLimit(2)
            }
            if !game.friendsLabel.isEmpty {
                Text("w/ \(game.friendsLabel)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
                    .lineLimit(1)
            }
            Text("\(game.playerStats.count) player lines · \(game.photos.count) photo\(game.photos.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(DesignTokens.cardSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    GamesView(externalFriendFilter: .constant(nil))
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
