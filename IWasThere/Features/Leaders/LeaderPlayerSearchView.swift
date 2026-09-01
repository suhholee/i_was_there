import SwiftUI
import SwiftData
import UIKit

/// Search all qualifying batters and pitchers under the current Leaders filters.
struct LeaderPlayerSearchView: View {
    @Binding var isPresented: Bool

    let league: League
    let games: [AttendedGame]
    let season: Int?
    let teamID: Int?
    let minPlateAppearances: Int
    let minBattersFaced: Int

    @State private var query = ""
    @State private var players: [LeaderboardEngine.SearchPlayerResult] = []

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPlayers: [LeaderboardEngine.SearchPlayerResult] {
        guard !trimmedQuery.isEmpty else { return [] }
        return players.filter { row in
            row.playerName.localizedCaseInsensitiveContains(trimmedQuery)
                || row.jerseyNumber.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if players.isEmpty {
                    ContentUnavailableView(
                        "No players match filters",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Adjust Leaders filters or minimum playing time in Settings.")
                    )
                } else if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Search players",
                        systemImage: "magnifyingglass",
                        description: Text("Type a player name or jersey number from your log.")
                    )
                } else if filteredPlayers.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filteredPlayers) { row in
                        NavigationLink {
                            PlayerDetailView(
                                playerID: row.playerID,
                                playerName: row.playerName,
                                jerseyNumber: row.jerseyNumber,
                                teamID: row.teamID,
                                prefersPitching: row.isPitcher && !row.isBatter,
                                league: league
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.playerName)
                                    .font(.headline)
                                    .foregroundStyle(DesignTokens.primaryText)
                                Text("\(row.roleLabel) · \(row.aggregate.games) game\(row.aggregate.games == 1 ? "" : "s") · \(summary(for: row))")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.secondaryText)
                            }
                        }
                        .listRowBackground(DesignTokens.surface)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Search players")
            .navigationBarTitleDisplayMode(.inline)
            .tint(DesignTokens.primaryText)
            .searchable(text: $query, prompt: "Player name or number")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                        .foregroundStyle(DesignTokens.primaryText)
                }
            }
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear(perform: loadPlayers)
        }
        .tint(DesignTokens.primaryText)
    }

    private func summary(for row: LeaderboardEngine.SearchPlayerResult) -> String {
        switch (row.isBatter, row.isPitcher) {
        case (true, false):
            return "AVG \(LeaderboardEngine.BatterCategory.avg.display(row.aggregate))"
        case (false, true):
            return "ERA \(LeaderboardEngine.PitcherCategory.era.display(row.aggregate))"
        case (true, true):
            return "AVG \(LeaderboardEngine.BatterCategory.avg.display(row.aggregate)) · ERA \(LeaderboardEngine.PitcherCategory.era.display(row.aggregate))"
        default:
            return ""
        }
    }

    private func close() {
        dismissKeyboard()
        isPresented = false
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func loadPlayers() {
        players = LeaderboardEngine.searchablePlayers(
            from: games,
            season: season,
            teamID: teamID,
            minPlateAppearances: minPlateAppearances,
            minBattersFaced: minBattersFaced
        )
    }
}
