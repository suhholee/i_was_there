import Foundation

struct RosterPlayerCandidate: Identifiable, Hashable, Sendable {
    let playerID: Int
    let name: String
    let jerseyNumber: String
    let teamID: Int
    let league: League
    let position: String

    var id: Int { playerID }
}

enum FavoritePlayerCatalog {
    static func loadCandidates(mlbTeamID: Int?, kboTeamID: Int?) async -> [RosterPlayerCandidate] {
        async let mlbRows = loadMLB(teamID: mlbTeamID)
        async let kboRows = loadKBO(teamID: kboTeamID)
        let mlb = (try? await mlbRows) ?? []
        let kbo = (try? await kboRows) ?? []
        return (mlb + kbo).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func loadMLB(teamID: Int?) async throws -> [RosterPlayerCandidate] {
        guard let teamID, teamID > 0 else { return [] }
        let roster = try await MLBClient.shared.teamRoster(teamID: teamID)
        return roster.map { entry in
            RosterPlayerCandidate(
                playerID: entry.person.id,
                name: entry.person.fullName,
                jerseyNumber: entry.jerseyNumber ?? "",
                teamID: teamID,
                league: .mlb,
                position: entry.position?.abbreviation ?? ""
            )
        }
    }

    private static func loadKBO(teamID: Int?) async throws -> [RosterPlayerCandidate] {
        guard let teamID, teamID > 0, let team = KBOTeamCatalog.team(id: teamID) else { return [] }
        let season = Calendar.current.component(.year, from: Date())
        let players = try await KBOClient.shared.players(season: season)
        return players.values
            .filter { $0.teamCode.uppercased() == team.code.uppercased() }
            .map { player in
                RosterPlayerCandidate(
                    playerID: player.id,
                    name: player.name,
                    jerseyNumber: player.jerseyNumber,
                    teamID: teamID,
                    league: .kbo,
                    position: player.position
                )
            }
    }
}
