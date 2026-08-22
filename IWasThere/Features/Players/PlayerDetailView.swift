import SwiftUI
import SwiftData

struct PlayerDetailView: View {
    let playerID: Int
    let playerName: String
    let jerseyNumber: String
    let teamID: Int
    let prefersPitching: Bool

    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var games: [AttendedGame]
    @State private var person: MLBPersonDetail?
    @State private var hittingSplits: [MLBSeasonSplit] = []
    @State private var pitchingSplits: [MLBSeasonSplit] = []
    @State private var selectedSeason: Int = Calendar.current.component(.year, from: Date())
    @State private var loadError: String?
    @State private var isLoading = false

    private var attendedSeasons: [Int] {
        let years = Set(
            games.flatMap { game in
                game.playerStats
                    .filter { $0.playerID == playerID }
                    .map { _ in game.season }
            }
        )
        return years.sorted(by: >)
    }

    private var seasonOptions: [Int] {
        var years = Set(attendedSeasons)
        years.formUnion(hittingSplits.compactMap { Int($0.season ?? "") })
        years.formUnion(pitchingSplits.compactMap { Int($0.season ?? "") })
        years.insert(Calendar.current.component(.year, from: Date()))
        return years.sorted(by: >)
    }

    private var attendedAggregate: LeaderboardEngine.PlayerAggregate? {
        let rows = LeaderboardEngine.aggregates(
            from: games,
            season: selectedSeason,
            pitchers: prefersPitching
        )
        return rows.first { $0.playerID == playerID }
    }

    private var attendedEither: LeaderboardEngine.PlayerAggregate? {
        attendedAggregate
            ?? LeaderboardEngine.aggregates(from: games, season: selectedSeason, pitchers: !prefersPitching)
            .first { $0.playerID == playerID }
    }

    private var totalHitting: MLBSeasonSplit? {
        hittingSplits.first { Int($0.season ?? "") == selectedSeason }
    }

    private var totalPitching: MLBSeasonSplit? {
        pitchingSplits.first { Int($0.season ?? "") == selectedSeason }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                seasonPicker

                sectionCard(title: "Attended (\(selectedSeason))") {
                    if let attended = attendedEither {
                        attendedStats(attended)
                    } else {
                        Text("No attended lines for this player in \(selectedSeason).")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.secondaryText)
                    }
                }

                sectionCard(title: "Total season (\(selectedSeason))") {
                    if isLoading {
                        ProgressView()
                            .tint(DesignTokens.accent)
                    } else if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.loseRed)
                    } else {
                        totalStatsBlock
                    }
                }
            }
            .padding(16)
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .navigationTitle(playerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DesignTokens.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadRemote()
        }
        .refreshable {
            await loadRemote(force: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            JerseyCardView(
                number: person?.primaryNumber ?? jerseyNumber,
                name: person?.fullName ?? playerName,
                subtitle: headerSubtitle,
                valueLabel: prefersPitching ? "P" : (person?.primaryPosition?.abbreviation ?? "BAT"),
                theme: TeamTheme.forTeamID(person?.currentTeam?.id ?? teamID)
            )

            if let person {
                HStack(spacing: 12) {
                    if let bats = person.batSide?.code {
                        metaChip("Bats \(bats)")
                    }
                    if let throwsHand = person.pitchHand?.code {
                        metaChip("Throws \(throwsHand)")
                    }
                    if let height = person.height {
                        metaChip(height)
                    }
                    if let weight = person.weight {
                        metaChip("\(weight) lb")
                    }
                }
            }
        }
    }

    private var headerSubtitle: String {
        let team = person?.currentTeam?.name
            ?? MLBTeamCatalog.team(id: teamID)?.name
            ?? "MLB"
        let pos = person?.primaryPosition?.abbreviation ?? ""
        if pos.isEmpty { return team }
        return "\(team) · \(pos)"
    }

    private var seasonPicker: some View {
        Menu {
            ForEach(seasonOptions, id: \.self) { year in
                Button(verbatimYear(year)) { selectedSeason = year }
            }
        } label: {
            HStack {
                Text(verbatim: "Season \(selectedSeason)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(DesignTokens.primaryText)
            .padding(12)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var totalStatsBlock: some View {
        let showHitting = totalHitting != nil || !prefersPitching
        let showPitching = totalPitching != nil || prefersPitching

        if totalHitting == nil && totalPitching == nil {
            Text(verbatim: "No MLB season line found for \(selectedSeason) yet.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)
        } else {
            if showHitting, let hit = totalHitting {
                Text("Hitting")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
                remoteHitting(hit.stat)
            }
            if showPitching, let pitch = totalPitching {
                if totalHitting != nil { Divider().opacity(0.3) }
                Text("Pitching")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
                remotePitching(pitch.stat)
            }
            Text(selectedSeason == Calendar.current.component(.year, from: Date())
                   ? "Current season is season-to-date from MLB Stats API. Pull to refresh."
                   : "Full-season totals from MLB Stats API.")
                .font(.caption2)
                .foregroundStyle(DesignTokens.secondaryText)
        }
    }

    private func attendedStats(_ row: LeaderboardEngine.PlayerAggregate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(row.games) attended game\(row.games == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)

            if row.isPitcher || prefersPitching {
                statLine("IP", row.inningsPitchedDisplay)
                statLine("ERA", StatFormulas.formatRate(row.era, digits: 2))
                statLine("WHIP", StatFormulas.formatRate(row.whip, digits: 2))
                statLine("K", "\(row.strikeouts)")
                statLine("BB", "\(row.walksAllowed)")
            } else {
                statLine("AVG", StatFormulas.formatAverage(row.battingAverage))
                statLine("OPS", StatFormulas.formatAverage(row.ops))
                statLine("HR", "\(row.homeRuns)")
                statLine("RBI", "\(row.rbi)")
                statLine("H/AB", "\(row.hits)/\(row.atBats)")
            }
        }
    }

    private func remoteHitting(_ stat: MLBSeasonStatLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statLine("G", "\(stat.gamesPlayed ?? 0)")
            statLine("AVG", stat.avg ?? "—")
            statLine("OPS", stat.ops ?? "—")
            statLine("HR", "\(stat.homeRuns ?? 0)")
            statLine("RBI", "\(stat.rbi ?? 0)")
            statLine("H/AB", "\(stat.hits ?? 0)/\(stat.atBats ?? 0)")
        }
    }

    private func remotePitching(_ stat: MLBSeasonStatLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statLine("G", "\(stat.gamesPlayed ?? 0)")
            statLine("GS", "\(stat.gamesStarted ?? 0)")
            statLine("IP", stat.inningsPitched ?? "—")
            statLine("ERA", stat.era ?? "—")
            statLine("WHIP", stat.whip ?? "—")
            statLine("K", "\(stat.strikeOuts ?? 0)")
            statLine("SV", "\(stat.saves ?? 0)")
            if let w = stat.wins, let l = stat.losses {
                statLine("W-L", "\(w)-\(l)")
            }
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText)
        }
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DesignTokens.surface)
            .clipShape(Capsule())
    }

    private func loadRemote(force: Bool = false) async {
        if !force, person != nil, (!hittingSplits.isEmpty || !pitchingSplits.isEmpty) { return }
        isLoading = true
        loadError = nil
        do {
            async let personTask = MLBClient.shared.person(id: playerID)
            async let hitTask = MLBClient.shared.playerStats(personID: playerID, group: .hitting)
            async let pitchTask = MLBClient.shared.playerStats(personID: playerID, group: .pitching)
            person = try await personTask
            hittingSplits = (try? await hitTask) ?? []
            pitchingSplits = (try? await pitchTask) ?? []
            if !seasonOptions.contains(selectedSeason), let first = seasonOptions.first {
                selectedSeason = first
            }
        } catch {
            loadError = "Couldn’t load MLB totals. Pull to retry."
        }
        isLoading = false
    }
}

private func verbatimYear(_ year: Int) -> String {
    String(year)
}
