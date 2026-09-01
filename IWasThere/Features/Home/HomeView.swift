import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.teamTheme) private var teamTheme
    @Binding var selectedTab: AppTab
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var showingAddGame = false
    @State private var seasonWins: Int?
    @State private var seasonLosses: Int?
    @State private var seasonDraws: Int?
    @State private var seasonPct: String?
    @State private var seasonLoadFailed = false
    @State private var isLoadingSeason = false

    private var profile: UserProfile? { profiles.first }
    private var activeLeague: League { profile?.league ?? .mlb }
    private var favoriteTeamID: Int? { profile?.favoriteTeamID(for: activeLeague) }

    private var games: [AttendedGame] {
        allGames.filter { $0.resolvedLeague == activeLeague }
    }

    private var attendance: LeaderboardEngine.AttendanceRecord {
        LeaderboardEngine.favoriteAttendance(games: games, favoriteTeamID: favoriteTeamID)
    }

    private var topBatters: [LeaderboardEngine.PlayerAggregate] {
        LeaderboardEngine.batterLeaders(
            from: games,
            category: homeBatterCategory,
            limit: 3,
            minPlateAppearances: profile?.homeMinPlateAppearances ?? 0
        )
    }

    private var topPitchers: [LeaderboardEngine.PlayerAggregate] {
        LeaderboardEngine.pitcherLeaders(
            from: games,
            category: .era,
            limit: 3,
            minBattersFaced: profile?.homeMinBattersFaced ?? 0
        )
    }

    private var favoriteBatters: [LeaderboardEngine.PlayerAggregate] {
        guard let favoriteTeamID else { return [] }
        return LeaderboardEngine.batterLeaders(
            from: games,
            category: homeBatterCategory,
            teamID: favoriteTeamID,
            limit: 3
        )
    }

    private var favoritePitchers: [LeaderboardEngine.PlayerAggregate] {
        guard let favoriteTeamID else { return [] }
        return LeaderboardEngine.pitcherLeaders(
            from: games,
            category: .era,
            teamID: favoriteTeamID,
            limit: 3
        )
    }

    /// KBO box lines lack full OPS inputs; prefer AVG on Home.
    private var homeBatterCategory: LeaderboardEngine.BatterCategory {
        activeLeague == .kbo ? .avg : .ops
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Button {
                        showingAddGame = true
                    } label: {
                        Label("Add \(activeLeague.title) game", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(teamTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    favoriteTeamCard

                    if !games.isEmpty {
                        if favoriteTeamID != nil {
                            miniLeadersSection(
                                title: "\(favoriteTeamName) leaders",
                                batters: favoriteBatters,
                                pitchers: favoritePitchers
                            )
                        }
                        miniLeadersSection(title: "Your leaders", batters: topBatters, pitchers: topPitchers)
                        latestGameCard
                    } else {
                        ContentUnavailableView {
                            Label("No \(activeLeague.title) games logged", systemImage: "baseball.diamond.bases")
                        } description: {
                            Text("Add a game to build your attendance diary and leaders.")
                                .foregroundStyle(DesignTokens.secondaryText)
                        }
                        .foregroundStyle(DesignTokens.primaryText)
                    }
                }
                .padding()
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .tint(DesignTokens.primaryText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingAddGame) {
                AddGameView(league: activeLeague)
                    .environment(\.modelContext, modelContext)
            }
            .task(id: "\(activeLeague.rawValue)-\(favoriteTeamID ?? -1)") {
                await loadSeasonRecord()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let teamID = favoriteTeamID {
                TeamLogoImage(teamID: teamID, size: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("#iWasThere")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let name = profileDisplayName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            leagueMenu
                .layoutPriority(1)
        }
    }

    private var leagueMenu: some View {
        Menu {
            ForEach(League.allCases) { league in
                Button {
                    saveLeague(league)
                } label: {
                    if league == activeLeague {
                        Label(league.title, systemImage: "checkmark")
                    } else {
                        Text(league.title)
                    }
                }
            }
        } label: {
            DropdownMenuLabel(title: activeLeague.title, style: .chip)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(DesignTokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }

    private func saveLeague(_ league: League) {
        ensureProfile()
        guard let profile = profiles.first else { return }
        profile.league = league
        try? modelContext.save()
    }

    private var favoriteTeamCard: some View {
        Group {
            if favoriteTeamID != nil && !games.isEmpty {
                Button {
                    selectedTab = .games
                } label: {
                    favoriteTeamCardContent
                }
                .buttonStyle(.plain)
            } else {
                favoriteTeamCardContent
            }
        }
    }

    private var favoriteTeamCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(favoriteTitle)
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            if favoriteTeamID == nil {
                Text("Pick a favorite \(activeLeague.title) team in Settings for season vs attendance W%.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else if games.isEmpty {
                Text("Log a game where \(favoriteTeamName) played to start your attendance record.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        recordBlocks
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        recordBlocks
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(
                colors: [teamTheme.primary.opacity(0.35), DesignTokens.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func miniLeadersSection(
        title: String,
        batters: [LeaderboardEngine.PlayerAggregate],
        pitchers: [LeaderboardEngine.PlayerAggregate]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            if batters.isEmpty && pitchers.isEmpty {
                Text("No matching player lines yet.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                if let batter = batters.first {
                    NavigationLink {
                        PlayerDetailView(
                            playerID: batter.playerID,
                            playerName: batter.playerName,
                            jerseyNumber: batter.jerseyNumber,
                            teamID: batter.teamID,
                            prefersPitching: false,
                            league: activeLeague
                        )
                    } label: {
                        JerseyCardView(
                            number: batter.jerseyNumber,
                            name: batter.playerName,
                            subtitle: "Top batter · \(homeBatterCategory.title) · \(gamesLabel(batter.games))",
                            valueLabel: homeBatterCategory.display(batter),
                            theme: TeamTheme.forTeamID(batter.teamID),
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                }
                if let pitcher = pitchers.first {
                    NavigationLink {
                        PlayerDetailView(
                            playerID: pitcher.playerID,
                            playerName: pitcher.playerName,
                            jerseyNumber: pitcher.jerseyNumber,
                            teamID: pitcher.teamID,
                            prefersPitching: true,
                            league: activeLeague
                        )
                    } label: {
                        JerseyCardView(
                            number: pitcher.jerseyNumber,
                            name: pitcher.playerName,
                            subtitle: "Top pitcher · ERA · \(gamesLabel(pitcher.games))",
                            valueLabel: LeaderboardEngine.PitcherCategory.era.display(pitcher),
                            theme: TeamTheme.forTeamID(pitcher.teamID),
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var latestGameCard: some View {
        if let latest = games.first {
            NavigationLink {
                GameDetailView(game: latest)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest game")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.primaryText)
                    Text("\(latest.awayTeamName) \(latest.awayScore)–\(latest.homeScore) \(latest.homeTeamName)")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                    Text(latest.startersLabel)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(DesignTokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recordBlocks: some View {
        recordBlock(
            title: "Attendance",
            record: attendance.recordLabel,
            pct: attendance.winPercentageLabel,
            footnote: attendance.games == 0
                ? "No favorite-team games yet"
                : "When you were there"
        )
        Divider().background(DesignTokens.secondaryText.opacity(0.3))
        recordBlock(
            title: "Season",
            record: seasonRecordLabel,
            pct: seasonPctLabel,
            footnote: seasonFootnote,
            isLoading: isLoadingSeason
        )
    }

    private func recordBlock(
        title: String,
        record: String,
        pct: String,
        footnote: String,
        isLoading: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            if isLoading {
                ProgressView()
                    .tint(DesignTokens.accent)
                    .padding(.vertical, 4)
            } else {
                Text(record)
                    .font(ScaledTypography.record)
                    .foregroundStyle(DesignTokens.primaryText)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(pct)
                    .font(ScaledTypography.recordPct)
                    .foregroundStyle(DesignTokens.accent)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(seasonLoadFailed && title == "Season" ? DesignTokens.loseRed : DesignTokens.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gamesLabel(_ count: Int) -> String {
        "\(count)G"
    }

    private var favoriteTitle: String {
        favoriteTeamID == nil ? "Favorite team" : favoriteTeamName
    }

    private var profileDisplayName: String? {
        let name = profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private var favoriteTeamName: String {
        guard let id = favoriteTeamID else { return "Favorite team" }
        switch activeLeague {
        case .mlb:
            return MLBTeamCatalog.team(id: id)?.name ?? profile?.favoriteTeamAbbr ?? "Favorite team"
        case .kbo:
            return KBOTeamCatalog.team(id: id)?.name ?? profile?.favoriteKBOTeamAbbr ?? "Favorite team"
        }
    }

    private var seasonRecordLabel: String {
        guard let wins = seasonWins, let losses = seasonLosses else { return "—" }
        if activeLeague == .kbo, let draws = seasonDraws, draws > 0 {
            return "\(wins)W \(losses)L \(draws)D"
        }
        return "\(wins)W \(losses)L"
    }

    private var seasonPctLabel: String {
        StatFormulas.formatWinPercentage(raw: seasonPct)
    }

    private var seasonFootnote: String {
        if isLoadingSeason { return "Loading standings…" }
        if seasonLoadFailed { return "Couldn't load standings" }
        return "\(activeLeague.title) standings"
    }

    private func loadSeasonRecord() async {
        seasonWins = nil
        seasonLosses = nil
        seasonDraws = nil
        seasonPct = nil
        seasonLoadFailed = false
        isLoadingSeason = false
        guard let favoriteTeamID else { return }

        isLoadingSeason = true
        defer { isLoadingSeason = false }

        let season = games.map(\.season).max()
            ?? Calendar.current.component(.year, from: Date())

        do {
            switch activeLeague {
            case .mlb:
                let response = try await MLBClient.shared.standings(season: season)
                let match = response.records
                    .flatMap(\.teamRecords)
                    .first { $0.team.id == favoriteTeamID }
                if let match {
                    seasonWins = match.wins
                    seasonLosses = match.losses
                    seasonPct = match.winningPercentage
                } else {
                    seasonLoadFailed = true
                }
            case .kbo:
                let rows = try await KBOClient.shared.standings(season: season)
                if let match = rows.first(where: { $0.teamID == favoriteTeamID }) {
                    seasonWins = match.wins
                    seasonLosses = match.losses
                    seasonDraws = match.draws
                    seasonPct = match.winningPercentage
                } else {
                    seasonLoadFailed = true
                }
            }
        } catch {
            seasonLoadFailed = true
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(\.teamTheme, TeamTheme.forTeamID(119))
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
