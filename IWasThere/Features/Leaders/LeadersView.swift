import SwiftUI
import SwiftData

struct LeadersView: View {
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var games: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var segment: LeaderSegment = .batters
    @State private var batterCategory: LeaderboardEngine.BatterCategory = .ops
    @State private var pitcherCategory: LeaderboardEngine.PitcherCategory = .era
    /// `0` = all seasons in the log
    @State private var seasonFilter: Int = 0
    /// `0` = all teams
    @State private var teamFilter: Int = 0
    @State private var batterPosition: LeaderboardEngine.BatterPositionFilter = .all
    @State private var pitcherRole: LeaderboardEngine.PitcherRoleFilter = .all
    @State private var displayedRows: [LeaderboardEngine.PlayerAggregate] = []
    @State private var cachedMVPCounts: [Int: Int] = [:]
    @State private var mvpCacheKey: String = ""

    private var favoriteTeamID: Int? { profiles.first?.favoriteTeamID }

    private var seasonsInLog: [Int] {
        Array(Set(games.map(\.season))).sorted(by: >)
    }

    private var teamsInLog: [MLBTeamInfo] {
        var seen = Set<Int>()
        var result: [MLBTeamInfo] = []
        for game in games {
            for id in [game.homeTeamID, game.awayTeamID] {
                guard seen.insert(id).inserted else { continue }
                if let known = MLBTeamCatalog.team(id: id) {
                    result.append(known)
                } else {
                    let name = game.homeTeamID == id ? game.homeTeamName : game.awayTeamName
                    result.append(MLBTeamInfo(id: id, name: name, abbreviation: "TEAM"))
                }
            }
        }
        return MLBTeamCatalog.orderedForPicker(favoring: favoriteTeamID, from: result)
    }

    private var teamIDFilter: Int? { teamFilter == 0 ? nil : teamFilter }
    private var seasonValue: Int? { seasonFilter == 0 ? nil : seasonFilter }

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
                        "No attendance leaders yet",
                        systemImage: "tshirt",
                        description: Text("Log the games you have attended to view your leaders.")
                    )
                    .foregroundStyle(DesignTokens.primaryText)
                    .frame(maxHeight: .infinity)
                } else if displayedRows.isEmpty {
                    ContentUnavailableView(
                        "No players match",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Try another team, position, or role filter.")
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
                                        prefersPitching: row.isPitcher
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
            .navigationTitle("Leaders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { refreshRows() }
            .onChange(of: segment) { _, _ in refreshRows() }
            .onChange(of: batterCategory) { _, _ in refreshRows() }
            .onChange(of: pitcherCategory) { _, _ in refreshRows() }
            .onChange(of: seasonFilter) { _, _ in refreshRows(invalidateMVP: true) }
            .onChange(of: teamFilter) { _, _ in refreshRows() }
            .onChange(of: batterPosition) { _, _ in refreshRows() }
            .onChange(of: pitcherRole) { _, _ in refreshRows() }
            .onChange(of: games.map(\.mlbGamePk)) { _, _ in refreshRows(invalidateMVP: true) }
        }
    }

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    if segment == .batters {
                        ForEach(LeaderboardEngine.BatterCategory.allCases) { category in
                            Button(category.title) { batterCategory = category }
                        }
                    } else {
                        ForEach(LeaderboardEngine.PitcherCategory.allCases) { category in
                            Button(category.title) { pitcherCategory = category }
                        }
                    }
                } label: {
                    filterChip(title: currentCategoryTitle)
                }

                Menu {
                    Button("All teams") { teamFilter = 0 }
                    ForEach(teamsInLog) { team in
                        Button(MLBTeamCatalog.pickerLabel(for: team, favoriteID: favoriteTeamID)) {
                            teamFilter = team.id
                        }
                    }
                } label: {
                    filterChip(title: teamFilterLabel)
                }

                if segment == .batters {
                    Menu {
                        ForEach(LeaderboardEngine.BatterPositionFilter.allCases) { position in
                            Button(position.title) { batterPosition = position }
                        }
                    } label: {
                        filterChip(title: batterPosition.title)
                    }
                } else {
                    Menu {
                        ForEach(LeaderboardEngine.PitcherRoleFilter.allCases) { role in
                            Button(role.title) { pitcherRole = role }
                        }
                    } label: {
                        filterChip(title: pitcherRole.title)
                    }
                }

                Menu {
                    Button("All seasons") { seasonFilter = 0 }
                    ForEach(seasonsInLog, id: \.self) { year in
                        Button(YearFormat.string(year)) { seasonFilter = year }
                    }
                } label: {
                    filterChip(title: seasonFilter == 0 ? "All seasons" : YearFormat.string(seasonFilter))
                }
            }
            .padding(.horizontal)
        }
    }

    private var teamFilterLabel: String {
        if teamFilter == 0 { return "All teams" }
        if let team = teamsInLog.first(where: { $0.id == teamFilter }) {
            return MLBTeamCatalog.pickerLabel(for: team, favoriteID: favoriteTeamID)
        }
        return "Team"
    }

    private func filterChip(title: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(DesignTokens.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignTokens.surface)
        .clipShape(Capsule())
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

    private func refreshRows(invalidateMVP: Bool = false) {
        let pitchers = segment == .pitchers
        let key = "\(seasonFilter)-\(pitchers)-\(games.map(\.mlbGamePk))"
        if invalidateMVP || key != mvpCacheKey {
            cachedMVPCounts = LeaderboardEngine.mvpCounts(
                from: games,
                season: seasonValue,
                pitchers: pitchers
            )
            mvpCacheKey = key
        }

        let next: [LeaderboardEngine.PlayerAggregate]
        switch segment {
        case .batters:
            next = LeaderboardEngine.batterLeaders(
                from: games,
                category: batterCategory,
                season: seasonValue,
                teamID: teamIDFilter,
                position: batterPosition,
                mvpCounts: cachedMVPCounts
            )
        case .pitchers:
            next = LeaderboardEngine.pitcherLeaders(
                from: games,
                category: pitcherCategory,
                season: seasonValue,
                teamID: teamIDFilter,
                role: pitcherRole,
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

private enum LeaderSegment: String, CaseIterable, Identifiable {
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

#Preview {
    LeadersView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
