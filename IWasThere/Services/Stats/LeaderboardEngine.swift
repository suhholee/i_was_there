import Foundation

/// Attendance-scoped aggregates: sum counting stats across games, then rate once.
enum LeaderboardEngine {
    struct PlayerAggregate: Identifiable, Hashable {
        let playerID: Int
        var playerName: String
        var jerseyNumber: String
        var teamID: Int
        let isPitcher: Bool
        var games: Int
        /// Most recent field position seen while aggregating.
        var position: String = ""
        /// Dominant pitcher role across filtered appearances.
        var pitcherRole: String = ""
        /// Times this player was Game MVP across attended games.
        var mvpCount: Int = 0

        var atBats: Int = 0
        var hits: Int = 0
        var homeRuns: Int = 0
        var rbi: Int = 0
        var walks: Int = 0
        var hitByPitch: Int = 0
        var sacFlies: Int = 0
        var totalBases: Int = 0
        var plateAppearances: Int = 0
        var doubles: Int = 0
        var triples: Int = 0
        var strikeOutsBatting: Int = 0
        var runs: Int = 0

        var inningsPitchedOuts: Int = 0
        var earnedRuns: Int = 0
        var strikeouts: Int = 0
        var hitsAllowed: Int = 0
        var walksAllowed: Int = 0
        var battersFaced: Int = 0

        var id: Int { playerID }

        var effectivePlateAppearances: Int {
            plateAppearances > 0 ? plateAppearances : atBats
        }

        var lastName: String {
            guard let last = playerName.split(separator: " ").last else { return playerName }
            return String(last).uppercased()
        }

        var battingAverage: Double? {
            StatFormulas.battingAverage(hits: hits, atBats: atBats)
        }

        var ops: Double? {
            StatFormulas.ops(
                hits: hits,
                walks: walks,
                hitByPitch: hitByPitch,
                atBats: atBats,
                sacFlies: sacFlies,
                totalBases: totalBases
            )
        }

        var era: Double? {
            StatFormulas.era(earnedRuns: earnedRuns, outs: inningsPitchedOuts)
        }

        var whip: Double? {
            StatFormulas.whip(hits: hitsAllowed, walks: walksAllowed, outs: inningsPitchedOuts)
        }

        var inningsPitchedDisplay: String {
            StatFormulas.formatIP(outs: inningsPitchedOuts)
        }
    }

    enum BatterPositionFilter: String, CaseIterable, Identifiable {
        case all
        case c = "C"
        case first = "1B"
        case second = "2B"
        case third = "3B"
        case ss = "SS"
        case lf = "LF"
        case cf = "CF"
        case rf = "RF"
        case dh = "DH"
        case of = "OF"
        case util = "UTIL"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All positions"
            case .c: "C"
            case .first: "1B"
            case .second: "2B"
            case .third: "3B"
            case .ss: "SS"
            case .lf: "LF"
            case .cf: "CF"
            case .rf: "RF"
            case .dh: "DH"
            case .of: "OF"
            case .util: "UTIL / PH"
            }
        }

        func matches(_ position: String) -> Bool {
            let p = position.uppercased()
            switch self {
            case .all: return true
            case .of: return p == "OF" || p == "LF" || p == "CF" || p == "RF"
            case .util: return p == "PH" || p == "PR" || p == "DH" || p == "UTIL" || p.isEmpty
            default: return p == rawValue
            }
        }
    }

    enum PitcherRoleFilter: String, CaseIterable, Identifiable {
        case all
        case sp = "SP"
        case rp = "RP"
        case cl = "CL"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All roles"
            case .sp: "Starting"
            case .rp: "Relief"
            case .cl: "Closing"
            }
        }

        func matches(_ role: String) -> Bool {
            switch self {
            case .all: return true
            default: return role.uppercased() == rawValue
            }
        }
    }

    enum BatterCategory: String, CaseIterable, Identifiable {
        case avg, ops, hr, rbi, hits, runs, mvp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .avg: "AVG"
            case .ops: "OPS"
            case .hr: "HR"
            case .rbi: "RBI"
            case .hits: "H"
            case .runs: "R"
            case .mvp: "MVP"
            }
        }

        var higherIsBetter: Bool { true }

        func value(for row: PlayerAggregate) -> Double? {
            switch self {
            case .avg: row.battingAverage
            case .ops: row.ops
            case .hr: Double(row.homeRuns)
            case .rbi: Double(row.rbi)
            case .hits: Double(row.hits)
            case .runs: Double(row.runs)
            case .mvp: Double(row.mvpCount)
            }
        }

        func qualifies(_ row: PlayerAggregate) -> Bool {
            switch self {
            case .avg, .ops: row.atBats >= 1
            case .hr, .rbi, .hits, .runs: row.plateAppearances >= 1 || row.atBats >= 1
            case .mvp: row.mvpCount >= 1
            }
        }

        func display(_ row: PlayerAggregate) -> String {
            switch self {
            case .avg:
                return formatRate(row.battingAverage)
            case .ops:
                return formatOPS(row.ops)
            case .hr:
                return "\(row.homeRuns)"
            case .rbi:
                return "\(row.rbi)"
            case .hits:
                return "\(row.hits)"
            case .runs:
                return "\(row.runs)"
            case .mvp:
                return "\(row.mvpCount)"
            }
        }

        func value(for stat: GamePlayerStat) -> Double? {
            switch self {
            case .avg: stat.battingAverage
            case .ops: stat.ops
            case .hr: Double(stat.homeRuns)
            case .rbi: Double(stat.rbi)
            case .hits: Double(stat.hits)
            case .runs: Double(stat.runs)
            case .mvp: nil
            }
        }

        func qualifies(_ stat: GamePlayerStat) -> Bool {
            switch self {
            case .avg, .ops: stat.atBats >= 1
            case .hr, .rbi, .hits, .runs: stat.plateAppearances >= 1 || stat.atBats >= 1
            case .mvp: true
            }
        }

        func display(for stat: GamePlayerStat) -> String {
            switch self {
            case .avg:
                return formatRate(stat.battingAverage) + " AVG"
            case .ops:
                guard let ops = stat.ops else { return "— OPS" }
                return String(format: "%.3f OPS", ops)
            case .hr:
                return "\(stat.homeRuns) HR"
            case .rbi:
                return "\(stat.rbi) RBI"
            case .hits:
                return "\(stat.hits) H"
            case .runs:
                return "\(stat.runs) R"
            case .mvp:
                return "Game MVP"
            }
        }
    }

    enum PitcherCategory: String, CaseIterable, Identifiable {
        case era, whip, so, ip, mvp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .era: "ERA"
            case .whip: "WHIP"
            case .so: "K"
            case .ip: "IP"
            case .mvp: "MVP"
            }
        }

        var higherIsBetter: Bool {
            switch self {
            case .era, .whip: false
            case .so, .ip, .mvp: true
            }
        }

        func value(for row: PlayerAggregate) -> Double? {
            switch self {
            case .era: row.era
            case .whip: row.whip
            case .so: Double(row.strikeouts)
            case .ip: Double(row.inningsPitchedOuts)
            case .mvp: Double(row.mvpCount)
            }
        }

        func qualifies(_ row: PlayerAggregate) -> Bool {
            switch self {
            case .mvp: row.mvpCount >= 1
            default: row.inningsPitchedOuts >= 3
            }
        }

        func display(_ row: PlayerAggregate) -> String {
            switch self {
            case .era:
                return formatERA(row.era)
            case .whip:
                return formatWHIP(row.whip)
            case .so:
                return "\(row.strikeouts)"
            case .ip:
                return row.inningsPitchedDisplay
            case .mvp:
                return "\(row.mvpCount)"
            }
        }

        func value(for stat: GamePlayerStat) -> Double? {
            switch self {
            case .era: stat.era
            case .whip: stat.whip
            case .so: Double(stat.strikeouts)
            case .ip: Double(stat.inningsPitchedOuts)
            case .mvp: nil
            }
        }

        func qualifies(_ stat: GamePlayerStat) -> Bool {
            switch self {
            case .mvp: true
            default: stat.inningsPitchedOuts >= 3
            }
        }

        func display(for stat: GamePlayerStat) -> String {
            switch self {
            case .era:
                return formatERA(stat.era) + " ERA"
            case .whip:
                return formatWHIP(stat.whip) + " WHIP"
            case .so:
                return "\(stat.strikeouts) K"
            case .ip:
                return StatFormulas.formatIP(outs: stat.inningsPitchedOuts) + " IP"
            case .mvp:
                return "Game MVP"
            }
        }
    }

    static func batterCategories(for league: League) -> [BatterCategory] {
        switch league {
        case .mlb:
            return Array(BatterCategory.allCases)
        case .kbo:
            return [.avg, .hits, .runs, .rbi, .hr, .mvp]
        }
    }

    static func resolvedBatterCategory(
        rawValue: String,
        league: League
    ) -> BatterCategory {
        let allowed = batterCategories(for: league)
        guard let parsed = BatterCategory(rawValue: rawValue),
              allowed.contains(parsed) else {
            return league == .kbo ? .avg : .ops
        }
        return parsed
    }

    static func resolvedPitcherCategory(rawValue: String) -> PitcherCategory {
        guard let parsed = PitcherCategory(rawValue: rawValue) else { return .era }
        return parsed
    }

    static func gameLeaderBatter(
        in game: AttendedGame,
        category: BatterCategory
    ) -> GamePlayerStat? {
        if category == .mvp {
            return gameMVPs(in: game).batter
        }
        let batters = game.playerStats.filter { category.qualifies($0) }
        return batters.max { lhs, rhs in
            let left = category.value(for: lhs) ?? -.infinity
            let right = category.value(for: rhs) ?? -.infinity
            if left == right { return lhs.playerName < rhs.playerName }
            return left < right
        }
    }

    static func gameLeaderPitcher(
        in game: AttendedGame,
        category: PitcherCategory
    ) -> GamePlayerStat? {
        if category == .mvp {
            return gameMVPs(in: game).pitcher
        }
        let pitchers = game.playerStats.filter { category.qualifies($0) }
        return pitchers.max { lhs, rhs in
            let left = category.value(for: lhs) ?? (category.higherIsBetter ? -.infinity : .infinity)
            let right = category.value(for: rhs) ?? (category.higherIsBetter ? -.infinity : .infinity)
            if left == right { return lhs.playerName < rhs.playerName }
            return category.higherIsBetter ? left < right : left > right
        }
    }

    struct AttendanceRecord: Equatable {
        let wins: Int
        let losses: Int

        var games: Int { wins + losses }

        var winPercentage: Double? {
            guard games > 0 else { return nil }
            return Double(wins) / Double(games)
        }

        var recordLabel: String {
            "\(wins)W \(losses)L"
        }

        var winPercentageLabel: String {
            StatFormulas.formatWinPercentage(winPercentage)
        }
    }

    static func favoriteAttendanceTogether(
        games: [AttendedGame],
        mlbFavoriteTeamID: Int?,
        kboFavoriteTeamID: Int?
    ) -> AttendanceRecord {
        var wins = 0
        var losses = 0
        for game in games {
            let favoriteTeamID: Int?
            switch game.resolvedLeague {
            case .mlb: favoriteTeamID = mlbFavoriteTeamID
            case .kbo: favoriteTeamID = kboFavoriteTeamID
            }
            guard let favoriteTeamID else { continue }
            switch game.favoriteTeamWon(favoriteTeamID: favoriteTeamID) {
            case true?: wins += 1
            case false?: losses += 1
            case nil: break
            }
        }
        return AttendanceRecord(wins: wins, losses: losses)
    }

    static func favoriteAttendance(
        games: [AttendedGame],
        favoriteTeamID: Int?
    ) -> AttendanceRecord {
        guard let favoriteTeamID else { return AttendanceRecord(wins: 0, losses: 0) }
        var wins = 0
        var losses = 0
        for game in games {
            switch game.favoriteTeamWon(favoriteTeamID: favoriteTeamID) {
            case true?: wins += 1
            case false?: losses += 1
            case nil: break
            }
        }
        return AttendanceRecord(wins: wins, losses: losses)
    }

    static func aggregates(
        from games: [AttendedGame],
        season: Int? = nil,
        pitchers: Bool,
        teamID: Int? = nil,
        batterPosition: BatterPositionFilter = .all,
        pitcherRole: PitcherRoleFilter = .all
    ) -> [PlayerAggregate] {
        let scoped = season.map { year in games.filter { $0.season == year } } ?? games
        var map: [Int: PlayerAggregate] = [:]
        var roleCounts: [Int: [String: Int]] = [:]

        for game in scoped {
            for stat in game.playerStats {
                let isBatterLine = stat.plateAppearances > 0 || stat.atBats > 0
                let isPitcherLine = stat.inningsPitchedOuts > 0
                if pitchers {
                    guard isPitcherLine else { continue }
                } else {
                    guard isBatterLine else { continue }
                }

                if let teamID, stat.teamID != teamID { continue }

                let role: String
                if pitchers {
                    role = stat.resolvedPitcherRole(in: game)
                    guard pitcherRole.matches(role) else { continue }
                } else {
                    role = ""
                    guard batterPosition.matches(stat.position) else { continue }
                }

                var row = map[stat.playerID] ?? PlayerAggregate(
                    playerID: stat.playerID,
                    playerName: stat.playerName,
                    jerseyNumber: stat.jerseyNumber,
                    teamID: stat.teamID,
                    isPitcher: pitchers,
                    games: 0
                )
                if pitchers {
                    var counts = roleCounts[stat.playerID] ?? [:]
                    counts[role, default: 0] += 1
                    roleCounts[stat.playerID] = counts
                }
                if !stat.playerName.isEmpty { row.playerName = stat.playerName }
                if !stat.jerseyNumber.isEmpty { row.jerseyNumber = stat.jerseyNumber }
                row.teamID = stat.teamID
                row.games += 1
                if !stat.position.isEmpty { row.position = stat.position }
                if !role.isEmpty { row.pitcherRole = role }
                row.atBats += stat.atBats
                row.hits += stat.hits
                row.homeRuns += stat.homeRuns
                row.rbi += stat.rbi
                row.walks += stat.walks
                row.hitByPitch += stat.hitByPitch
                row.sacFlies += stat.sacFlies
                row.totalBases += stat.totalBases
                row.plateAppearances += stat.plateAppearances
                row.doubles += stat.doubles
                row.triples += stat.triples
                row.strikeOutsBatting += stat.strikeOutsBatting
                row.runs += stat.runs
                row.inningsPitchedOuts += stat.inningsPitchedOuts
                row.earnedRuns += stat.earnedRuns
                row.strikeouts += stat.strikeouts
                row.hitsAllowed += stat.hitsAllowed
                row.walksAllowed += stat.walksAllowed
                let faced = stat.battersFaced > 0
                    ? stat.battersFaced
                    : StatFormulas.estimatedBattersFaced(
                        hits: stat.hitsAllowed,
                        walks: stat.walksAllowed,
                        strikeouts: stat.strikeouts,
                        outsRecorded: stat.inningsPitchedOuts
                    )
                row.battersFaced += faced
                map[stat.playerID] = row
            }
        }

        for (playerID, counts) in roleCounts {
            guard var row = map[playerID] else { continue }
            if let best = counts.max(by: { $0.value < $1.value })?.key {
                row.pitcherRole = best
                map[playerID] = row
            }
        }
        return Array(map.values)
    }

    static func batterLeaders(
        from games: [AttendedGame],
        category: BatterCategory,
        season: Int? = nil,
        teamID: Int? = nil,
        position: BatterPositionFilter = .all,
        limit: Int = 20,
        minPlateAppearances: Int = 0,
        mvpCounts: [Int: Int]? = nil
    ) -> [PlayerAggregate] {
        var rows = aggregates(
            from: games,
            season: season,
            pitchers: false,
            teamID: teamID,
            batterPosition: position
        )
        applyMVPCounts(&rows, from: games, season: season, pitchers: false, cached: mvpCounts)
        rows = rows.filter {
            category.qualifies($0) && $0.effectivePlateAppearances >= minPlateAppearances
        }
        return sorted(rows, by: category.value, higherIsBetter: category.higherIsBetter, limit: limit)
    }

    struct SearchPlayerResult: Identifiable, Hashable {
        let playerID: Int
        var playerName: String
        var jerseyNumber: String
        var teamID: Int
        var aggregate: PlayerAggregate
        var isBatter: Bool
        var isPitcher: Bool

        var id: Int { playerID }

        var roleLabel: String {
            switch (isBatter, isPitcher) {
            case (true, true): "Batter · Pitcher"
            case (true, false): "Batter"
            case (false, true): "Pitcher"
            default: ""
            }
        }
    }

    /// Players eligible for leader search for the active Batters/Pitchers segment.
    static func searchablePlayers(
        from games: [AttendedGame],
        pitchersOnly: Bool,
        season: Int? = nil,
        teamID: Int? = nil,
        minPlateAppearances: Int = 0,
        minBattersFaced: Int = 0
    ) -> [SearchPlayerResult] {
        if pitchersOnly {
            let pitcherMVP = mvpCounts(from: games, season: season, pitchers: true)
            let pitchers = pitcherLeaders(
                from: games,
                category: .ip,
                season: season,
                teamID: teamID,
                role: .all,
                limit: 1_000,
                minBattersFaced: minBattersFaced,
                mvpCounts: pitcherMVP
            )
            return pitchers.map {
                SearchPlayerResult(
                    playerID: $0.playerID,
                    playerName: $0.playerName,
                    jerseyNumber: $0.jerseyNumber,
                    teamID: $0.teamID,
                    aggregate: $0,
                    isBatter: false,
                    isPitcher: true
                )
            }
            .sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
        }

        let batterMVP = mvpCounts(from: games, season: season, pitchers: false)
        let batters = batterLeaders(
            from: games,
            category: .hits,
            season: season,
            teamID: teamID,
            position: .all,
            limit: 1_000,
            minPlateAppearances: minPlateAppearances,
            mvpCounts: batterMVP
        )
        return batters.map {
            SearchPlayerResult(
                playerID: $0.playerID,
                playerName: $0.playerName,
                jerseyNumber: $0.jerseyNumber,
                teamID: $0.teamID,
                aggregate: $0,
                isBatter: true,
                isPitcher: false
            )
        }
        .sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
    }

    /// All qualifying batters and pitchers for search (ignores Batters/Pitchers segment).
    static func searchablePlayers(
        from games: [AttendedGame],
        season: Int? = nil,
        teamID: Int? = nil,
        minPlateAppearances: Int = 0,
        minBattersFaced: Int = 0
    ) -> [SearchPlayerResult] {
        let batterMVP = mvpCounts(from: games, season: season, pitchers: false)
        let pitcherMVP = mvpCounts(from: games, season: season, pitchers: true)

        let batters = batterLeaders(
            from: games,
            category: .hits,
            season: season,
            teamID: teamID,
            position: .all,
            limit: 1_000,
            minPlateAppearances: minPlateAppearances,
            mvpCounts: batterMVP
        )
        let pitchers = pitcherLeaders(
            from: games,
            category: .ip,
            season: season,
            teamID: teamID,
            role: .all,
            limit: 1_000,
            minBattersFaced: minBattersFaced,
            mvpCounts: pitcherMVP
        )

        var batterByID = Dictionary(uniqueKeysWithValues: batters.map { ($0.playerID, $0) })
        var pitcherByID = Dictionary(uniqueKeysWithValues: pitchers.map { ($0.playerID, $0) })
        let allIDs = Set(batterByID.keys).union(pitcherByID.keys)

        return allIDs.map { playerID in
            let batter = batterByID[playerID]
            let pitcher = pitcherByID[playerID]
            let merged = mergeSearchAggregates(batter: batter, pitcher: pitcher)
            return SearchPlayerResult(
                playerID: playerID,
                playerName: merged.playerName,
                jerseyNumber: merged.jerseyNumber,
                teamID: merged.teamID,
                aggregate: merged,
                isBatter: batter != nil,
                isPitcher: pitcher != nil
            )
        }
        .sorted { $0.playerName.localizedCaseInsensitiveCompare($1.playerName) == .orderedAscending }
    }

    private static func mergeSearchAggregates(
        batter: PlayerAggregate?,
        pitcher: PlayerAggregate?
    ) -> PlayerAggregate {
        guard let batter else { return pitcher! }
        guard let pitcher else { return batter }
        var merged = batter
        merged.games = max(batter.games, pitcher.games)
        merged.mvpCount = max(batter.mvpCount, pitcher.mvpCount)
        merged.inningsPitchedOuts = pitcher.inningsPitchedOuts
        merged.earnedRuns = pitcher.earnedRuns
        merged.strikeouts = pitcher.strikeouts
        merged.hitsAllowed = pitcher.hitsAllowed
        merged.walksAllowed = pitcher.walksAllowed
        merged.battersFaced = pitcher.battersFaced
        merged.pitcherRole = pitcher.pitcherRole
        return merged
    }

    static func pitcherLeaders(
        from games: [AttendedGame],
        category: PitcherCategory,
        season: Int? = nil,
        teamID: Int? = nil,
        role: PitcherRoleFilter = .all,
        limit: Int = 20,
        minBattersFaced: Int = 0,
        mvpCounts: [Int: Int]? = nil
    ) -> [PlayerAggregate] {
        var rows = aggregates(
            from: games,
            season: season,
            pitchers: true,
            teamID: teamID,
            pitcherRole: role
        )
        applyMVPCounts(&rows, from: games, season: season, pitchers: true, cached: mvpCounts)
        rows = rows.filter {
            category.qualifies($0) && $0.battersFaced >= minBattersFaced
        }
        return sorted(rows, by: category.value, higherIsBetter: category.higherIsBetter, limit: limit)
    }

    /// Precompute MVP tallies once; reuse across team/position/category filter changes.
    static func mvpCounts(
        from games: [AttendedGame],
        season: Int?,
        pitchers: Bool
    ) -> [Int: Int] {
        let scoped = season.map { year in games.filter { $0.season == year } } ?? games
        var counts: [Int: Int] = [:]
        for game in scoped {
            let pair = gameMVPs(in: game)
            let winner = pitchers ? pair.pitcher : pair.batter
            guard let winner else { continue }
            counts[winner.playerID, default: 0] += 1
        }
        return counts
    }

    /// Per-game MVPs: best batter line and best pitcher line (when each qualifies).
    /// Batter score ≈ OPS + 0.12×HR + 0.03×RBI; pitcher ≈ IP/K/ER weighting.
    static func gameMVPs(in game: AttendedGame) -> (batter: GamePlayerStat?, pitcher: GamePlayerStat?) {
        let batters = game.playerStats.filter { $0.plateAppearances > 0 || $0.atBats > 0 }
        let pitchers = game.playerStats.filter { $0.inningsPitchedOuts > 0 }
        let batter = batters.max(by: { batterMVPScore($0) < batterMVPScore($1) })
        let pitcher = pitchers.max(by: { pitcherMVPScore($0) < pitcherMVPScore($1) })
        return (batter, pitcher)
    }

    /// Legacy single-MVP helper (batter preferred, else pitcher).
    static func gameMVP(in game: AttendedGame) -> GamePlayerStat? {
        let pair = gameMVPs(in: game)
        return pair.batter ?? pair.pitcher
    }

    static func batterMVPScore(_ stat: GamePlayerStat) -> Double {
        let ops = stat.ops ?? 0
        return ops + Double(stat.homeRuns) * 0.12 + Double(stat.rbi) * 0.03
    }

    static func pitcherMVPScore(_ stat: GamePlayerStat) -> Double {
        let ip = Double(stat.inningsPitchedOuts) / 3.0
        return ip * 2.0 + Double(stat.strikeouts) * 0.35 - Double(stat.earnedRuns) * 0.75
    }

    private static func applyMVPCounts(
        _ rows: inout [PlayerAggregate],
        from games: [AttendedGame],
        season: Int?,
        pitchers: Bool,
        cached: [Int: Int]? = nil
    ) {
        let counts = cached ?? mvpCounts(from: games, season: season, pitchers: pitchers)
        for i in rows.indices {
            rows[i].mvpCount = counts[rows[i].playerID] ?? 0
        }
    }

    private static func sorted(
        _ rows: [PlayerAggregate],
        by value: (PlayerAggregate) -> Double?,
        higherIsBetter: Bool,
        limit: Int
    ) -> [PlayerAggregate] {
        rows.sorted { lhs, rhs in
            let lv = value(lhs) ?? (higherIsBetter ? -Double.infinity : Double.infinity)
            let rv = value(rhs) ?? (higherIsBetter ? -Double.infinity : Double.infinity)
            if lv == rv { return lhs.playerName < rhs.playerName }
            return higherIsBetter ? lv > rv : lv < rv
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func formatRate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value).replacingOccurrences(of: "0.", with: ".")
    }

    private static func formatOPS(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }

    private static func formatERA(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    private static func formatWHIP(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    struct FavoritePlayerSummary: Identifiable, Hashable {
        let playerID: Int
        var playerName: String
        var jerseyNumber: String
        var teamID: Int
        var batter: PlayerAggregate?
        var pitcher: PlayerAggregate?

        var id: Int { playerID }

        var prefersPitching: Bool {
            pitcher != nil && batter == nil
        }
    }

    static func favoritePlayerSummaries(
        from games: [AttendedGame],
        playerIDs: [Int],
        league: League,
        batterCategory: BatterCategory,
        pitcherCategory: PitcherCategory,
        minPlateAppearances: Int = 0,
        minBattersFaced: Int = 0,
        playerMeta: [Int: FavoritePlayerMeta] = [:]
    ) -> [FavoritePlayerSummary] {
        guard !playerIDs.isEmpty else { return [] }

        let batterMVP = mvpCounts(from: games, season: nil, pitchers: false)
        let pitcherMVP = mvpCounts(from: games, season: nil, pitchers: true)
        let batters = batterLeaders(
            from: games,
            category: batterCategory,
            limit: 5_000,
            minPlateAppearances: minPlateAppearances,
            mvpCounts: batterMVP
        )
        let pitchers = pitcherLeaders(
            from: games,
            category: pitcherCategory,
            limit: 5_000,
            minBattersFaced: minBattersFaced,
            mvpCounts: pitcherMVP
        )
        let batterByID = Dictionary(uniqueKeysWithValues: batters.map { ($0.playerID, $0) })
        let pitcherByID = Dictionary(uniqueKeysWithValues: pitchers.map { ($0.playerID, $0) })

        return playerIDs.compactMap { playerID in
            let batter = batterByID[playerID]
            let pitcher = pitcherByID[playerID]
            guard batter != nil || pitcher != nil else {
                if let meta = playerMeta[playerID] {
                    return FavoritePlayerSummary(
                        playerID: playerID,
                        playerName: meta.name,
                        jerseyNumber: meta.jerseyNumber,
                        teamID: meta.teamID,
                        batter: nil,
                        pitcher: nil
                    )
                }
                return FavoritePlayerSummary(
                    playerID: playerID,
                    playerName: "Player \(playerID)",
                    jerseyNumber: "",
                    teamID: batter?.teamID ?? pitcher?.teamID ?? 0,
                    batter: nil,
                    pitcher: nil
                )
            }
            let merged = mergeSearchAggregates(batter: batter, pitcher: pitcher)
            return FavoritePlayerSummary(
                playerID: playerID,
                playerName: merged.playerName,
                jerseyNumber: merged.jerseyNumber,
                teamID: merged.teamID,
                batter: batter,
                pitcher: pitcher
            )
        }
    }
}
