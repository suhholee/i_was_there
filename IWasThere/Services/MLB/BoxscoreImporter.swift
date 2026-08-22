import Foundation
import SwiftData

enum GameImportError: LocalizedError {
    case duplicateGame(Int)
    case notFinal
    case missingScores

    var errorDescription: String? {
        switch self {
        case .duplicateGame(let pk):
            return "Game \(pk) is already in your log."
        case .notFinal:
            return "Only Final games can be added so the box score is complete."
        case .missingScores:
            return "This game is missing a final score."
        }
    }
}

enum BoxscoreImporter {
    /// Builds a local `AttendedGame` + player snapshots from schedule row + boxscore.
    /// Attendance-scoped rates are computed later via `StatFormulas` (not stored).
    static func makeAttendedGame(
        from scheduleGame: MLBScheduleGame,
        boxscore: MLBBoxscoreResponse,
        existingGamePks: Set<Int>
    ) throws -> AttendedGame {
        guard !existingGamePks.contains(scheduleGame.gamePk) else {
            throw GameImportError.duplicateGame(scheduleGame.gamePk)
        }
        guard scheduleGame.status.abstractGameState == "Final"
            || scheduleGame.status.detailedState == "Final"
        else {
            throw GameImportError.notFinal
        }

        let awayScore = scheduleGame.teams.away.score
        let homeScore = scheduleGame.teams.home.score
        guard let awayScore, let homeScore else {
            throw GameImportError.missingScores
        }

        let gameDate = MLBDateParsing.date(fromOfficial: scheduleGame.officialDate) ?? .now
        let season = Calendar(identifier: .gregorian).component(.year, from: gameDate)

        let game = AttendedGame(
            mlbGamePk: scheduleGame.gamePk,
            gameDate: gameDate,
            season: season,
            venueName: scheduleGame.venue?.name ?? "",
            homeTeamID: scheduleGame.teams.home.team.id,
            awayTeamID: scheduleGame.teams.away.team.id,
            homeTeamName: scheduleGame.teams.home.team.name,
            awayTeamName: scheduleGame.teams.away.team.name,
            homeScore: homeScore,
            awayScore: awayScore,
            homeWon: scheduleGame.teams.home.isWinner ?? (homeScore > awayScore),
            awayWon: scheduleGame.teams.away.isWinner ?? (awayScore > homeScore)
        )

        var byPlayer: [Int: GamePlayerStat] = [:]

        for side in [boxscore.teams.away, boxscore.teams.home] {
            let teamID = side.team.id
            for batterID in side.batters {
                guard let player = side.players["ID\(batterID)"] else { continue }
                let batting = player.stats?.batting

                let row = byPlayer[batterID] ?? GamePlayerStat(
                    playerID: batterID,
                    playerName: player.person.fullName,
                    jerseyNumber: player.jerseyNumber ?? "",
                    teamID: teamID,
                    position: player.position?.abbreviation ?? "",
                    isPitcher: false
                )
                row.playerName = player.person.fullName
                row.jerseyNumber = player.jerseyNumber ?? row.jerseyNumber
                row.teamID = teamID
                row.position = player.position?.abbreviation ?? row.position
                if let batting {
                    row.atBats = batting.atBats ?? 0
                    row.hits = batting.hits ?? 0
                    row.homeRuns = batting.homeRuns ?? 0
                    row.rbi = batting.rbi ?? 0
                    row.walks = batting.baseOnBalls ?? 0
                    row.hitByPitch = batting.hitByPitch ?? 0
                    row.sacFlies = batting.sacFlies ?? 0
                    row.totalBases = batting.totalBases ?? 0
                    row.plateAppearances = batting.plateAppearances ?? 0
                    row.doubles = batting.doubles ?? 0
                    row.triples = batting.triples ?? 0
                    row.strikeOutsBatting = batting.strikeOuts ?? 0
                    row.runs = batting.runs ?? 0
                }
                byPlayer[batterID] = row
            }

            for pitcherID in side.pitchers {
                guard let player = side.players["ID\(pitcherID)"] else { continue }
                let pitching = player.stats?.pitching
                let outs = pitching?.outs
                    ?? StatFormulas.outs(fromInningsPitched: pitching?.inningsPitched)
                    ?? 0
                let row = byPlayer[pitcherID] ?? GamePlayerStat(
                    playerID: pitcherID,
                    playerName: player.person.fullName,
                    jerseyNumber: player.jerseyNumber ?? "",
                    teamID: teamID,
                    position: player.position?.abbreviation ?? "P",
                    isPitcher: true
                )
                row.isPitcher = true
                row.playerName = player.person.fullName
                row.jerseyNumber = player.jerseyNumber ?? row.jerseyNumber
                row.teamID = teamID
                if row.position.isEmpty {
                    row.position = player.position?.abbreviation ?? "P"
                }
                if let pitching {
                    row.inningsPitchedOuts = outs
                    row.earnedRuns = pitching.earnedRuns ?? 0
                    row.strikeouts = pitching.strikeOuts ?? 0
                    row.hitsAllowed = pitching.hits ?? 0
                    row.walksAllowed = pitching.baseOnBalls ?? 0
                    row.pitcherWins = pitching.wins ?? 0
                    row.pitcherLosses = pitching.losses ?? 0
                }
                byPlayer[pitcherID] = row
            }
        }

        game.playerStats = Array(byPlayer.values)
        return game
    }
}

enum MLBDateParsing {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(fromOfficial officialDate: String?) -> Date? {
        guard let officialDate else { return nil }
        return dayFormatter.date(from: officialDate)
    }

    static func scheduleQueryDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Use the calendar day the user picked in their local timezone.
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
