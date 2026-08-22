import Foundation
import SwiftData

/// Fills `awayStarterName` / `homeStarterName` for games saved before starters were stored.
enum StarterBackfill {
    @MainActor
    static func ensureStarters(for game: AttendedGame, modelContext: ModelContext) async {
        let awayEmpty = game.awayStarterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let homeEmpty = game.homeStarterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard awayEmpty || homeEmpty else { return }

        // Prefer local SP lines if pitcher roles were already imported.
        if awayEmpty,
           let local = game.playerStats.first(where: {
               $0.teamID == game.awayTeamID && $0.resolvedPitcherRole(in: game) == "SP"
           }) {
            game.awayStarterName = local.playerName
        }
        if homeEmpty,
           let local = game.playerStats.first(where: {
               $0.teamID == game.homeTeamID && $0.resolvedPitcherRole(in: game) == "SP"
           }) {
            game.homeStarterName = local.playerName
        }

        let stillAwayEmpty = game.awayStarterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let stillHomeEmpty = game.homeStarterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard stillAwayEmpty || stillHomeEmpty else {
            try? modelContext.save()
            return
        }

        do {
            let boxscore = try await MLBClient.shared.boxscore(gamePk: game.mlbGamePk)
            if stillAwayEmpty,
               let name = starterName(from: boxscore.teams.away) {
                game.awayStarterName = name
            }
            if stillHomeEmpty,
               let name = starterName(from: boxscore.teams.home) {
                game.homeStarterName = name
            }

            // Also stamp pitcher roles when missing so Leaders filters work.
            for side in [boxscore.teams.away, boxscore.teams.home] {
                for pitcherID in side.pitchers {
                    guard let player = side.players["ID\(pitcherID)"],
                          let row = game.playerStats.first(where: { $0.playerID == pitcherID }),
                          row.pitcherRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          let pitching = player.stats?.pitching
                    else { continue }
                    row.pitcherRole = BoxscoreImporter.pitcherRole(from: pitching)
                }
            }
            try? modelContext.save()
        } catch {
            // Leave placeholders; UI already shows "— vs —".
        }
    }

    static func starterName(from side: MLBBoxscoreTeam) -> String? {
        // True starter: gamesStarted == 1
        for pitcherID in side.pitchers {
            guard let player = side.players["ID\(pitcherID)"] else { continue }
            if (player.stats?.pitching?.gamesStarted ?? 0) > 0 {
                return player.person.fullName
            }
        }
        // Fallback: first pitcher listed in boxscore order
        if let firstID = side.pitchers.first,
           let player = side.players["ID\(firstID)"] {
            return player.person.fullName
        }
        return nil
    }
}
