import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.teamTheme) private var teamTheme
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var games: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var showingAddGame = false
    @State private var seasonWins: Int?
    @State private var seasonLosses: Int?
    @State private var seasonPct: String?
    @State private var seasonLoadFailed = false

    private var profile: UserProfile? { profiles.first }
    private var favoriteTeamID: Int? { profile?.favoriteTeamID }

    private var attendance: LeaderboardEngine.AttendanceRecord {
        LeaderboardEngine.favoriteAttendance(games: games, favoriteTeamID: favoriteTeamID)
    }

    private var topBatters: [LeaderboardEngine.PlayerAggregate] {
        LeaderboardEngine.batterLeaders(from: games, category: .ops, limit: 3)
    }

    private var topPitchers: [LeaderboardEngine.PlayerAggregate] {
        LeaderboardEngine.pitcherLeaders(from: games, category: .era, limit: 3)
    }

    private var favoriteBatters: [LeaderboardEngine.PlayerAggregate] {
        guard let favoriteTeamID else { return [] }
        return LeaderboardEngine.batterLeaders(
            from: games,
            category: .ops,
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Button {
                        showingAddGame = true
                    } label: {
                        Label("Add game", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(teamTheme.primary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    favoriteTeamCard

                    if !games.isEmpty {
                        miniLeadersSection(title: "Your leaders", batters: topBatters, pitchers: topPitchers)
                        if favoriteTeamID != nil {
                            miniLeadersSection(
                                title: "\(favoriteTeamName) leaders",
                                batters: favoriteBatters,
                                pitchers: favoritePitchers
                            )
                        }
                        latestGameCard
                    }
                }
                .padding()
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingAddGame) {
                AddGameView()
                    .environment(\.modelContext, modelContext)
            }
            .task(id: favoriteTeamID) {
                await loadSeasonRecord()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let teamID = favoriteTeamID,
               let url = MLBAssetURLs.teamSpotImage(teamID: teamID) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        Circle().fill(teamTheme.primary.opacity(0.4))
                    }
                }
                .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("#iWasThere")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText)
                if let name = profileDisplayName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                }
            }
        }
    }

    private var favoriteTeamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(favoriteTitle)
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            if favoriteTeamID == nil {
                Text("Pick a favorite team in Settings for season vs attendance W%.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else if games.isEmpty {
                Text("Log a game where \(favoriteTeamName) played to start your attendance record.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                HStack(alignment: .top, spacing: 16) {
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
                        footnote: seasonFootnote
                    )
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
                            prefersPitching: false
                        )
                    } label: {
                        JerseyCardView(
                            number: batter.jerseyNumber,
                            name: batter.playerName,
                            subtitle: "Top batter · OPS · \(batter.games)g",
                            valueLabel: LeaderboardEngine.BatterCategory.ops.display(batter),
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
                            prefersPitching: true
                        )
                    } label: {
                        JerseyCardView(
                            number: pitcher.jerseyNumber,
                            name: pitcher.playerName,
                            subtitle: "Top pitcher · ERA · \(pitcher.games)g",
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

    private func recordBlock(title: String, record: String, pct: String, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            Text(record)
                .font(.title2.weight(.heavy))
                .foregroundStyle(DesignTokens.primaryText)
                .monospacedDigit()
            Text(pct)
                .font(.title3.weight(.bold))
                .foregroundStyle(DesignTokens.accent)
                .monospacedDigit()
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(DesignTokens.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return MLBTeamCatalog.team(id: id)?.name ?? profile?.favoriteTeamAbbr ?? "Favorite team"
    }

    private var seasonRecordLabel: String {
        guard let wins = seasonWins, let losses = seasonLosses else { return "—" }
        return "\(wins)W \(losses)L"
    }

    private var seasonPctLabel: String {
        guard let seasonPct else { return "—" }
        if seasonPct.hasPrefix("0.") {
            return "." + seasonPct.dropFirst(2)
        }
        return seasonPct
    }

    private var seasonFootnote: String {
        if seasonLoadFailed { return "Couldn’t load standings" }
        if seasonWins == nil { return "Loading…" }
        return "MLB standings"
    }

    private func loadSeasonRecord() async {
        seasonWins = nil
        seasonLosses = nil
        seasonPct = nil
        seasonLoadFailed = false
        guard let favoriteTeamID else { return }

        let season = games.map(\.season).max()
            ?? Calendar.current.component(.year, from: Date())
        do {
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
        } catch {
            seasonLoadFailed = true
        }
    }
}

#Preview {
    HomeView()
        .environment(\.teamTheme, TeamTheme.forTeamID(119))
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
