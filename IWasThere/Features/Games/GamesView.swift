import SwiftUI
import SwiftData

struct GamesView: View {
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var games: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var showingAddGame = false
    /// `0` = All teams
    @State private var filterTeamID: Int = 0

    private var favoriteTeamID: Int? { profiles.first?.favoriteTeamID }

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

    private var filteredGames: [AttendedGame] {
        guard filterTeamID != 0 else { return games }
        return games.filter { $0.homeTeamID == filterTeamID || $0.awayTeamID == filterTeamID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.background.ignoresSafeArea()

                if games.isEmpty {
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "baseball.diamond.bases")
                    } description: {
                        Text("Log a Final MLB game to pull the box score into your 직관 diary.")
                            .foregroundStyle(DesignTokens.secondaryText)
                    } actions: {
                        Button("Add game") { showingAddGame = true }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignTokens.accent)
                    }
                    .foregroundStyle(DesignTokens.primaryText)
                } else {
                    VStack(spacing: 0) {
                        teamFilterBar
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                        if filteredGames.isEmpty {
                            ContentUnavailableView(
                                "No games for this team",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try another team filter.")
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
            .navigationTitle("Games")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddGame = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGame) {
                AddGameView()
            }
        }
    }

    private var selectedTeamFilterLabel: String {
        if filterTeamID == 0 { return "All teams" }
        if let team = teamsInLog.first(where: { $0.id == filterTeamID }) {
            return MLBTeamCatalog.pickerLabel(for: team, favoriteID: favoriteTeamID)
        }
        return "Team"
    }

    private var teamFilterBar: some View {
        Menu {
            Button("All teams") { filterTeamID = 0 }
            ForEach(teamsInLog) { team in
                Button(MLBTeamCatalog.pickerLabel(for: team, favoriteID: favoriteTeamID)) {
                    filterTeamID = team.id
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectedTeamFilterLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                if game.favoriteTeamWon(favoriteTeamID: favoriteTeamID) == true {
                    Text("WIN")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(DesignTokens.winGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.winGreen.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text("\(game.awayScore)–\(game.homeScore) · \(game.gameDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.cardSecondaryText)
            if !game.eventTitle.isEmpty {
                Text(game.eventTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
                    .lineLimit(2)
            }
            if !game.companions.isEmpty {
                Text("w/ \(game.companions)")
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
    GamesView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
