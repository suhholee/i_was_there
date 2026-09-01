import Foundation
import SwiftData

enum GameImportError: LocalizedError {
    case duplicateGame(Int)
    case duplicateGameKey(String)
    case notFinal
    case missingScores

    var errorDescription: String? {
        switch self {
        case .duplicateGame(let pk):
            return "Game \(pk) is already in your log."
        case .duplicateGameKey(let key):
            return "Game \(key) is already in your log."
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

        let calendarDay = MLBDateParsing.calendarDate(fromOfficial: scheduleGame.officialDate)
            ?? MLBDateParsing.calendarDate(fromFirstPitch: scheduleGame.gameDate)
            ?? Date()
        let firstPitch = MLBDateParsing.firstPitch(fromISO: scheduleGame.gameDate) ?? calendarDay
        let season = Calendar.current.component(.year, from: calendarDay)

        let game = AttendedGame(
            mlbGamePk: scheduleGame.gamePk,
            league: .mlb,
            gameKey: LeagueKey.mlb(scheduleGame.gamePk),
            gameDate: calendarDay,
            firstPitchAt: firstPitch,
            officialDateString: scheduleGame.officialDate
                ?? MLBDateParsing.scheduleQueryDate(from: calendarDay),
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
        game.gameTypeCode = scheduleGame.gameType ?? ""

        if let awayName = StarterBackfill.starterName(from: boxscore.teams.away) {
            game.awayStarterName = awayName
        }
        if let homeName = StarterBackfill.starterName(from: boxscore.teams.home) {
            game.homeStarterName = homeName
        }
        game.attendanceCount = Self.attendance(from: boxscore)

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
                let hasBattingLine = row.atBats > 0 || row.plateAppearances > 0 || row.hits > 0
                if hasBattingLine {
                    row.isPitcher = false
                } else {
                    row.isPitcher = true
                    if row.position.isEmpty {
                        row.position = player.position?.abbreviation ?? "P"
                    }
                }
                row.playerName = player.person.fullName
                row.jerseyNumber = player.jerseyNumber ?? row.jerseyNumber
                row.teamID = teamID
                if let pitching {
                    row.inningsPitchedOuts = outs
                    row.earnedRuns = pitching.earnedRuns ?? 0
                    row.strikeouts = pitching.strikeOuts ?? 0
                    row.hitsAllowed = pitching.hits ?? 0
                    row.walksAllowed = pitching.baseOnBalls ?? 0
                    row.battersFaced = pitching.battersFaced
                        ?? StatFormulas.estimatedBattersFaced(
                            hits: row.hitsAllowed,
                            walks: row.walksAllowed,
                            strikeouts: row.strikeouts,
                            outsRecorded: outs
                        )
                    row.pitcherWins = pitching.wins ?? 0
                    row.pitcherLosses = pitching.losses ?? 0
                    row.pitcherRole = Self.pitcherRole(from: pitching)
                }
                byPlayer[pitcherID] = row
            }
        }

        game.playerStats = Array(byPlayer.values)
        for stat in game.playerStats {
            stat.game = game
        }
        return game
    }

    /// SP from gamesStarted; CL from saves; otherwise RP.
    static func pitcherRole(from pitching: MLBPitchingStats) -> String {
        if (pitching.gamesStarted ?? 0) > 0 { return "SP" }
        if (pitching.saves ?? 0) > 0 { return "CL" }
        if let note = pitching.note?.uppercased(), note.contains("(S") || note.contains(" SV") {
            return "CL"
        }
        return "RP"
    }

    /// Parses boxscore info line `Att` → `46,105.` into an Int.
    static func attendance(from boxscore: MLBBoxscoreResponse) -> Int? {
        guard let lines = boxscore.info else { return nil }
        for line in lines {
            let label = (line.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard label == "att" || label == "attendance" else { continue }
            let raw = (line.value ?? "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            if let value = Int(raw), value > 0 { return value }
        }
        return nil
    }
}

enum MLBDateParsing {
    /// Interpret MLB `officialDate` (`yyyy-MM-dd`) as that calendar day in the
    /// **user's current timezone** (noon), so the displayed day never shifts.
    static func calendarDate(fromOfficial officialDate: String?) -> Date? {
        guard let officialDate else { return nil }
        let parts = officialDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)
    }

    /// Fallback calendar day from first-pitch ISO, using the user's timezone.
    static func calendarDate(fromFirstPitch iso: String?) -> Date? {
        guard let firstPitch = firstPitch(fromISO: iso) else { return nil }
        let cal = Calendar.current
        let parts = cal.dateComponents([.year, .month, .day], from: firstPitch)
        var noon = DateComponents()
        noon.year = parts.year
        noon.month = parts.month
        noon.day = parts.day
        noon.hour = 12
        return cal.date(from: noon)
    }

    static func firstPitch(fromISO iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    static func scheduleQueryDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
