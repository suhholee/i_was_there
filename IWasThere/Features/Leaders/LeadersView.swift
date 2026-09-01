import SwiftUI
import SwiftData

struct LeadersView: View {
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var segment: LeaderSegment = .batters
    @State private var batterCategory: LeaderboardEngine.BatterCategory = .avg
    @State private var pitcherCategory: LeaderboardEngine.PitcherCategory = .era
    /// `0` = all seasons in the log
    @State private var seasonFilter: Int = 0
    /// `0` = all teams
    @State private var teamFilter: Int = 0
    @State private var gamePhaseFilter: GamePhaseFilter = .all
    @State private var venueFilter: String = ""
    @State private var favoriteResultFilter: FavoriteResultFilter = .all
    @State private var friendFilter: String = ""
    @State private var batterPosition: LeaderboardEngine.BatterPositionFilter = .all
    @State private var pitcherRole: LeaderboardEngine.PitcherRoleFilter = .all
    @State private var displayedRows: [LeaderboardEngine.PlayerAggregate] = []
    @State private var cachedMVPCounts: [Int: Int] = [:]
    @State private var mvpCacheKey: String = ""
    @State private var isSearchingPlayers = false

    private var activeLeague: League { profiles.first?.league ?? .mlb }
    private var favoriteTeamID: Int? { profiles.first?.favoriteTeamID(for: activeLeague) }
    private var minPlateAppearances: Int { profiles.first?.homeMinPlateAppearances ?? 0 }
    private var minBattersFaced: Int { profiles.first?.homeMinBattersFaced ?? 0 }

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

    private var friendsInLog: [String] {
        GameLogFilter.friends(in: games)
    }

    private var filteredGames: [AttendedGame] {
        GameLogFilter.apply(
            to: games,
            season: seasonFilter == 0 ? nil : seasonFilter,
            teamID: teamFilter == 0 ? nil : teamFilter,
            phase: gamePhaseFilter,
            venue: venueFilter.isEmpty ? nil : venueFilter,
            favoriteResult: favoriteResultFilter,
            favoriteTeamID: favoriteTeamID,
            friend: friendFilter.isEmpty ? nil : friendFilter
        )
    }

    private var batterCategories: [LeaderboardEngine.BatterCategory] {
        switch activeLeague {
        case .mlb:
            return Array(LeaderboardEngine.BatterCategory.allCases)
        case .kbo:
            // BoxScore lines omit HR/OPS inputs for now.
            return [.avg, .hits, .runs, .rbi, .mvp]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Leaders", selection: $segment) {
                    ForEach(LeaderSegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                filtersBar

                if games.isEmpty {
                    ContentUnavailableView(
                        "No \(activeLeague.title) attendance leaders yet",
                        systemImage: "tshirt",
                        description: Text("Log the games you have attended to view your leaders.")
                    )
                    .foregroundStyle(DesignTokens.primaryText)
                    .frame(maxHeight: .infinity)
                } else if displayedRows.isEmpty {
                    ContentUnavailableView(
                        "No players match",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another filter, stadium, friend, or minimum playing time in Settings.")
                    )
                    .foregroundStyle(DesignTokens.primaryText)
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(displayedRows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink {
                                    PlayerDetailView(
                                        playerID: row.playerID,
                                        playerName: row.playerName,
                                        jerseyNumber: row.jerseyNumber,
                                        teamID: row.teamID,
                                        prefersPitching: segment == .pitchers,
                                        league: activeLeague
                                    )
                                } label: {
                                    JerseyCardView(
                                        number: row.jerseyNumber,
                                        name: row.playerName,
                                        subtitle: "#\(index + 1) · \(row.games) game\(row.games == 1 ? "" : "s") · \(currentCategoryTitle)",
                                        valueLabel: currentDisplay(row),
                                        theme: TeamTheme.forTeamID(row.teamID)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .transaction { $0.animation = nil }
                }
            }
            .padding(.top)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("\(activeLeague.title) Leaders")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DesignTokens.primaryText)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSearchingPlayers = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.primaryText)
                    .disabled(games.isEmpty)
                }
            }
            .sheet(isPresented: $isSearchingPlayers) {
                LeaderPlayerSearchView(
                    isPresented: $isSearchingPlayers,
                    league: activeLeague,
                    games: filteredGames,
                    season: nil,
                    teamID: nil,
                    minPlateAppearances: minPlateAppearances,
                    minBattersFaced: minBattersFaced
                )
            }
            .onAppear {
                normalizeBatterCategory()
                refreshRows()
            }
            .onChange(of: activeLeague) { _, _ in
                resetAttendanceFilters()
                normalizeBatterCategory()
            }
            .onChange(of: refreshTrigger) { _, _ in
                refreshRows(invalidateMVP: true)
            }
        }
    }

    private var refreshTrigger: LeadersRefreshTrigger {
        LeadersRefreshTrigger(
            league: activeLeague,
            segment: segment,
            batterCategory: batterCategory,
            pitcherCategory: pitcherCategory,
            seasonFilter: seasonFilter,
            teamFilter: teamFilter,
            gamePhaseFilter: gamePhaseFilter,
            venueFilter: venueFilter,
            favoriteResultFilter: favoriteResultFilter,
            friendFilter: friendFilter,
            batterPosition: batterPosition,
            pitcherRole: pitcherRole,
            minPlateAppearances: minPlateAppearances,
            minBattersFaced: minBattersFaced,
            gameKeys: games.map(\.mlbGamePk)
        )
    }

    private var filtersBar: some View {
        GameAttendanceFiltersBar(
            seasonFilter: $seasonFilter,
            teamFilter: $teamFilter,
            gamePhaseFilter: $gamePhaseFilter,
            venueFilter: $venueFilter,
            favoriteResultFilter: $favoriteResultFilter,
            friendFilter: $friendFilter,
            seasonsInLog: seasonsInLog,
            teamsInLog: teamsInLog,
            venuesInLog: venuesInLog,
            friendsInLog: friendsInLog,
            favoriteTeamID: favoriteTeamID,
            horizontalPadding: 16
        ) {
            Menu {
                if segment == .batters {
                    ForEach(batterCategories) { category in
                        Button(category.title) { batterCategory = category }
                    }
                } else {
                    ForEach(LeaderboardEngine.PitcherCategory.allCases) { category in
                        Button(category.title) { pitcherCategory = category }
                    }
                }
            } label: {
                FilterChip(title: currentCategoryTitle)
            }

            if segment == .batters {
                Menu {
                    ForEach(LeaderboardEngine.BatterPositionFilter.allCases) { position in
                        Button(position.title) { batterPosition = position }
                    }
                } label: {
                    FilterChip(title: batterPosition.title)
                }
            } else {
                Menu {
                    ForEach(LeaderboardEngine.PitcherRoleFilter.allCases) { role in
                        Button(role.title) { pitcherRole = role }
                    }
                } label: {
                    FilterChip(title: pitcherRole.title)
                }
            }
        }
    }

    private var currentCategoryTitle: String {
        segment == .batters ? batterCategory.title : pitcherCategory.title
    }

    private func currentDisplay(_ row: LeaderboardEngine.PlayerAggregate) -> String {
        switch segment {
        case .batters:
            return batterCategory.display(row)
        case .pitchers:
            return pitcherCategory.display(row)
        }
    }

    private func normalizeBatterCategory() {
        if !batterCategories.contains(batterCategory) {
            batterCategory = batterCategories.first ?? .avg
        }
    }

    private func resetAttendanceFilters() {
        seasonFilter = 0
        teamFilter = 0
        gamePhaseFilter = .all
        venueFilter = ""
        favoriteResultFilter = .all
        friendFilter = ""
    }

    private func refreshRows(invalidateMVP: Bool = false) {
        let pitchers = segment == .pitchers
        let key = "\(activeLeague.rawValue)-\(filteredGames.map(\.mlbGamePk))"
        if invalidateMVP || key != mvpCacheKey {
            cachedMVPCounts = LeaderboardEngine.mvpCounts(
                from: filteredGames,
                season: nil,
                pitchers: pitchers
            )
            mvpCacheKey = key
        }

        let next: [LeaderboardEngine.PlayerAggregate]
        switch segment {
        case .batters:
            next = LeaderboardEngine.batterLeaders(
                from: filteredGames,
                category: batterCategory,
                season: nil,
                teamID: nil,
                position: batterPosition,
                minPlateAppearances: minPlateAppearances,
                mvpCounts: cachedMVPCounts
            )
        case .pitchers:
            next = LeaderboardEngine.pitcherLeaders(
                from: filteredGames,
                category: pitcherCategory,
                season: nil,
                teamID: nil,
                role: pitcherRole,
                minBattersFaced: minBattersFaced,
                mvpCounts: cachedMVPCounts
            )
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            displayedRows = next
        }
    }
}

enum LeaderSegment: String, CaseIterable, Identifiable {
    case batters
    case pitchers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .batters: "Batters"
        case .pitchers: "Pitchers"
        }
    }
}

private struct LeadersRefreshTrigger: Equatable {
    let league: League
    let segment: LeaderSegment
    let batterCategory: LeaderboardEngine.BatterCategory
    let pitcherCategory: LeaderboardEngine.PitcherCategory
    let seasonFilter: Int
    let teamFilter: Int
    let gamePhaseFilter: GamePhaseFilter
    let venueFilter: String
    let favoriteResultFilter: FavoriteResultFilter
    let friendFilter: String
    let batterPosition: LeaderboardEngine.BatterPositionFilter
    let pitcherRole: LeaderboardEngine.PitcherRoleFilter
    let minPlateAppearances: Int
    let minBattersFaced: Int
    let gameKeys: [Int]
}

#Preview {
    LeadersView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
