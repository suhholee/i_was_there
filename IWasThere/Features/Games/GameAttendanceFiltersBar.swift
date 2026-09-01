import SwiftUI

struct GameFilterTeam: Identifiable {
    let id: Int
    let name: String
}

/// Shared attendance filters (season, team, phase, stadium, W/L, friend).
struct GameAttendanceFiltersBar<Prefix: View>: View {
    @Binding var seasonFilter: Int
    @Binding var teamFilter: Int
    @Binding var gamePhaseFilter: GamePhaseFilter
    @Binding var venueFilter: String
    @Binding var favoriteResultFilter: FavoriteResultFilter
    @Binding var friendFilter: String

    let seasonsInLog: [Int]
    let teamsInLog: [GameFilterTeam]
    let venuesInLog: [String]
    let friendsInLog: [String]
    let favoriteTeamID: Int?
    var horizontalPadding: CGFloat = 16
    @ViewBuilder var prefix: () -> Prefix

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                prefix()

                Menu {
                    Button("All seasons") { seasonFilter = 0 }
                    ForEach(seasonsInLog, id: \.self) { year in
                        Button {
                            seasonFilter = year
                        } label: {
                            YearFormat.text(year)
                        }
                    }
                } label: {
                    filterChip(title: seasonFilter == 0 ? "All seasons" : YearFormat.string(seasonFilter))
                }

                Menu {
                    Button("All teams") { teamFilter = 0 }
                    ForEach(teamsInLog) { team in
                        Button(pickerLabel(for: team)) {
                            teamFilter = team.id
                        }
                    }
                } label: {
                    filterChip(title: teamFilterLabel)
                }

                Menu {
                    ForEach(GamePhaseFilter.allCases) { phase in
                        Button(phase.title) { gamePhaseFilter = phase }
                    }
                } label: {
                    filterChip(title: gamePhaseFilter.title)
                }

                if !venuesInLog.isEmpty {
                    Menu {
                        Button("All stadiums") { venueFilter = "" }
                        ForEach(venuesInLog, id: \.self) { venue in
                            Button(venue) { venueFilter = venue }
                        }
                    } label: {
                        filterChip(title: venueFilter.isEmpty ? "All stadiums" : venueFilter)
                    }
                }

                if favoriteTeamID != nil {
                    Menu {
                        ForEach(FavoriteResultFilter.allCases) { result in
                            Button(result.title) { favoriteResultFilter = result }
                        }
                    } label: {
                        filterChip(title: favoriteResultFilter.title)
                    }
                }

                if !friendsInLog.isEmpty {
                    Menu {
                        Button("Anyone") { friendFilter = "" }
                        ForEach(friendsInLog, id: \.self) { friend in
                            Button(friend) { friendFilter = friend }
                        }
                    } label: {
                        filterChip(title: friendFilter.isEmpty ? "Anyone" : friendFilter)
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var teamFilterLabel: String {
        if teamFilter == 0 { return "All teams" }
        if let team = teamsInLog.first(where: { $0.id == teamFilter }) {
            return pickerLabel(for: team)
        }
        return "Team"
    }

    private func pickerLabel(for team: GameFilterTeam) -> String {
        if let favoriteTeamID, team.id == favoriteTeamID {
            return "\(team.name) ★"
        }
        return team.name
    }

    private func filterChip(title: String) -> some View {
        FilterChip(title: title)
    }
}

extension GameAttendanceFiltersBar where Prefix == EmptyView {
    init(
        seasonFilter: Binding<Int>,
        teamFilter: Binding<Int>,
        gamePhaseFilter: Binding<GamePhaseFilter>,
        venueFilter: Binding<String>,
        favoriteResultFilter: Binding<FavoriteResultFilter>,
        friendFilter: Binding<String>,
        seasonsInLog: [Int],
        teamsInLog: [GameFilterTeam],
        venuesInLog: [String],
        friendsInLog: [String],
        favoriteTeamID: Int?,
        horizontalPadding: CGFloat = 16
    ) {
        self._seasonFilter = seasonFilter
        self._teamFilter = teamFilter
        self._gamePhaseFilter = gamePhaseFilter
        self._venueFilter = venueFilter
        self._favoriteResultFilter = favoriteResultFilter
        self._friendFilter = friendFilter
        self.seasonsInLog = seasonsInLog
        self.teamsInLog = teamsInLog
        self.venuesInLog = venuesInLog
        self.friendsInLog = friendsInLog
        self.favoriteTeamID = favoriteTeamID
        self.horizontalPadding = horizontalPadding
        self.prefix = { EmptyView() }
    }
}

struct FilterChip: View {
    let title: String

    var body: some View {
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
}
