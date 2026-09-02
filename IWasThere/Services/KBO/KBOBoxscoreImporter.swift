import Foundation

enum KBOBoxscoreImporter {
    static func makeAttendedGame(
        from payload: KBOBoxPayload,
        existingGameKeys: Set<String>
    ) throws -> AttendedGame {
        let game = payload.game
        let key = LeagueKey.kbo(game.gameID)
        guard !existingGameKeys.contains(key) else {
            throw GameImportError.duplicateGameKey(game.gameID)
        }
        guard game.isFinal else {
            throw GameImportError.notFinal
        }

        let scores = derivedScores(from: payload.hitters)
        let awayScore = scores[game.awayCode] ?? 0
        let homeScore = scores[game.homeCode] ?? 0

        let awayResult = payload.teamRecords.first { $0.t_id == game.awayCode }?.result_sc
        let homeResult = payload.teamRecords.first { $0.t_id == game.homeCode }?.result_sc
        let awayWon = awayResult == "W" || (awayResult != "L" && awayScore > homeScore)
        let homeWon = homeResult == "W" || (homeResult != "L" && homeScore > awayScore)

        let calendarDay = calendarDate(fromGDt: game.gDt) ?? Date()
        let pk = LeagueKey.syntheticPk(forKBOGameID: game.gameID)

        let attended = AttendedGame(
            mlbGamePk: pk,
            league: .kbo,
            gameKey: key,
            kboGameID: game.gameID,
            gameDate: calendarDay,
            firstPitchAt: calendarDay,
            officialDateString: officialDateString(fromGDt: game.gDt),
            season: game.season,
            gameTypeCode: game.seriesID,
            stadiumCode: game.stadiumCode,
            venueName: KBOTeamCatalog.resolvedVenueName(
                apiName: payload.venueName,
                stadiumCode: game.stadiumCode,
                homeTeamCode: game.homeCode,
                homeTeamID: game.homeTeam.id
            ),
            homeTeamID: game.homeTeam.id,
            awayTeamID: game.awayTeam.id,
            homeTeamName: game.homeTeam.name,
            awayTeamName: game.awayTeam.name,
            homeScore: homeScore,
            awayScore: awayScore,
            homeWon: homeWon,
            awayWon: awayWon
        )

        if let starters = payload.starters {
            if let awayID = Int(starters.t_pit_p_id ?? "") {
                attended.awayStarterName = payload.players[awayID]?.name ?? ""
            }
            if let homeID = Int(starters.b_pit_p_id ?? "") {
                attended.homeStarterName = payload.players[homeID]?.name ?? ""
            }
        }

        var byPlayer: [Int: GamePlayerStat] = [:]

        for row in payload.hitters {
            guard let pid = Int(row.p_id ?? "") else { continue }
            let teamCode = row.tb_sc ?? ""
            let teamID = KBOTeamCatalog.id(forCode: teamCode)
            let person = payload.players[pid]
            let ab = intValue(row.ab_cn)
            let hits = intValue(row.hit_cn)
            let rbi = intValue(row.rbi_cn)
            let runs = intValue(row.run_cn)
            if ab == 0 && hits == 0 && rbi == 0 && runs == 0 { continue }

            let stat = byPlayer[pid] ?? GamePlayerStat(
                playerID: pid,
                playerName: person?.name ?? "Player \(pid)",
                jerseyNumber: person?.jerseyNumber ?? "",
                teamID: teamID,
                position: mapPosition(row.pos_if ?? person?.position ?? ""),
                isPitcher: false
            )
            stat.isPitcher = false
            stat.atBats += ab
            stat.plateAppearances += ab > 0 ? ab : 1
            stat.hits += hits
            stat.homeRuns += row.derivedHomeRuns
            stat.rbi += rbi
            stat.runs += runs
            if !stat.position.isEmpty || !(row.pos_if ?? "").isEmpty {
                stat.position = mapPosition(row.pos_if ?? stat.position)
            }
            byPlayer[pid] = stat
        }

        for row in payload.pitchers {
            guard let pid = Int(row.p_id ?? "") else { continue }
            let teamCode = row.tb_sc ?? ""
            let teamID = KBOTeamCatalog.id(forCode: teamCode)
            let person = payload.players[pid]
            let outs = intValue(row.inn2_cn)
            if outs == 0 && intValue(row.kk_cn) == 0 && intValue(row.er_cn) == 0 { continue }

            let existing = byPlayer[pid]
            let hasBattingLine = (existing?.atBats ?? 0) > 0
                || (existing?.plateAppearances ?? 0) > 0
                || (existing?.hits ?? 0) > 0
            let stat = existing ?? GamePlayerStat(
                playerID: pid,
                playerName: person?.name ?? "Player \(pid)",
                jerseyNumber: person?.jerseyNumber ?? "",
                teamID: teamID,
                position: "P",
                isPitcher: true
            )
            if hasBattingLine {
                stat.isPitcher = false
            } else {
                stat.isPitcher = true
                stat.position = "P"
            }
            stat.inningsPitchedOuts += outs
            stat.hitsAllowed += intValue(row.hit_cn)
            stat.strikeouts += intValue(row.kk_cn)
            stat.earnedRuns += intValue(row.er_cn)
            // Sports2i combines BB+HBP.
            stat.walksAllowed += intValue(row.bbhp_cn)
            stat.battersFaced += StatFormulas.estimatedBattersFaced(
                hits: intValue(row.hit_cn),
                walks: intValue(row.bbhp_cn),
                strikeouts: intValue(row.kk_cn),
                outsRecorded: outs
            )
            let role = pitcherRole(result: row.result_sc, turn: row.turn_no, starters: payload.starters, playerID: pid)
            if !role.isEmpty { stat.pitcherRole = role }
            if row.result_sc == "W" { stat.pitcherWins = 1 }
            if row.result_sc == "L" { stat.pitcherLosses = 1 }
            byPlayer[pid] = stat
        }

        attended.playerStats = Array(byPlayer.values)
        for stat in attended.playerStats {
            stat.game = attended
        }
        return attended
    }

    private static func derivedScores(from hitters: [KBOHitterBoxDTO]) -> [String: Int] {
        var runs: [String: Int] = [:]
        for row in hitters {
            guard let code = row.tb_sc else { continue }
            runs[code, default: 0] += intValue(row.run_cn)
        }
        return runs
    }

    private static func pitcherRole(result: String?, turn: String?, starters: KBOStarterDTO?, playerID: Int) -> String {
        if result == "S" { return "CL" }
        if let starters {
            let away = Int(starters.t_pit_p_id ?? "")
            let home = Int(starters.b_pit_p_id ?? "")
            if playerID == away || playerID == home { return "SP" }
        }
        if turn == "1" { return "SP" }
        return "RP"
    }

    private static func mapPosition(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        // Korean single-char / compound positions from Sports2i box.
        if trimmed.contains("투") || trimmed.uppercased() == "P" { return "P" }
        if trimmed.contains("포") { return "C" }
        if trimmed.contains("一") || trimmed.contains("1") { return "1B" }
        if trimmed.contains("二") || trimmed.contains("2") { return "2B" }
        if trimmed.contains("三") || trimmed.contains("3") { return "3B" }
        if trimmed.contains("유") { return "SS" }
        if trimmed.contains("좌") { return "LF" }
        if trimmed.contains("중") { return "CF" }
        if trimmed.contains("우") { return "RF" }
        if trimmed.contains("지") { return "DH" }
        return trimmed
    }

    private static func intValue(_ raw: String?) -> Int {
        Int(raw ?? "") ?? 0
    }

    private static func calendarDate(fromGDt gDt: String) -> Date? {
        guard gDt.count == 8,
              let y = Int(gDt.prefix(4)),
              let m = Int(gDt.dropFirst(4).prefix(2)),
              let d = Int(gDt.suffix(2))
        else { return nil }
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
    }

    private static func officialDateString(fromGDt gDt: String) -> String {
        guard gDt.count == 8 else { return gDt }
        let y = gDt.prefix(4)
        let m = gDt.dropFirst(4).prefix(2)
        let d = gDt.suffix(2)
        return "\(y)-\(m)-\(d)"
    }
}
