import Foundation

/// Attendance-scoped aggregates: sum counting stats across games, then rate once.
enum LeaderboardEngine {
    struct PlayerAggregate: Identifiable, Hashable {
        let playerID: Int
        let playerName: String
        let jerseyNumber: String
        let teamID: Int
        let isPitcher: Bool
        let games: Int
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

        var id: Int { playerID }

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
            guard let winPercentage else { return "—" }
            return String(format: "%.3f", winPercentage).replacingOccurrences(of: "0.", with: ".")
        }
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
            for stat in game.playerStats where stat.isPitcher == pitchers {
                if let teamID, stat.teamID != teamID { continue }
                if pitchers {
                    let role = stat.resolvedPitcherRole(in: game)
                    guard pitcherRole.matches(role) else { continue }
                } else {
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
                let role = pitchers ? stat.resolvedPitcherRole(in: game) : ""
                if pitchers {
                    var counts = roleCounts[stat.playerID] ?? [:]
                    counts[role, default: 0] += 1
                    roleCounts[stat.playerID] = counts
                }
                row = PlayerAggregate(
                    playerID: row.playerID,
                    playerName: stat.playerName.isEmpty ? row.playerName : stat.playerName,
                    jerseyNumber: stat.jerseyNumber.isEmpty ? row.jerseyNumber : stat.jerseyNumber,
                    teamID: stat.teamID,
                    isPitcher: pitchers,
                    games: row.games + 1,
                    position: stat.position.isEmpty ? row.position : stat.position,
                    pitcherRole: role.isEmpty ? row.pitcherRole : role,
                    atBats: row.atBats + stat.atBats,
                    hits: row.hits + stat.hits,
                    homeRuns: row.homeRuns + stat.homeRuns,
                    rbi: row.rbi + stat.rbi,
                    walks: row.walks + stat.walks,
                    hitByPitch: row.hitByPitch + stat.hitByPitch,
                    sacFlies: row.sacFlies + stat.sacFlies,
                    totalBases: row.totalBases + stat.totalBases,
                    plateAppearances: row.plateAppearances + stat.plateAppearances,
                    doubles: row.doubles + stat.doubles,
                    triples: row.triples + stat.triples,
                    strikeOutsBatting: row.strikeOutsBatting + stat.strikeOutsBatting,
                    runs: row.runs + stat.runs,
                    inningsPitchedOuts: row.inningsPitchedOuts + stat.inningsPitchedOuts,
                    earnedRuns: row.earnedRuns + stat.earnedRuns,
                    strikeouts: row.strikeouts + stat.strikeouts,
                    hitsAllowed: row.hitsAllowed + stat.hitsAllowed,
                    walksAllowed: row.walksAllowed + stat.walksAllowed
                )
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
        limit: Int = 20
    ) -> [PlayerAggregate] {
        var rows = aggregates(
            from: games,
            season: season,
            pitchers: false,
            teamID: teamID,
            batterPosition: position
        )
        applyMVPCounts(&rows, from: games, season: season, pitchers: false)
        rows = rows.filter { category.qualifies($0) }
        return sorted(rows, by: category.value, higherIsBetter: category.higherIsBetter, limit: limit)
    }

    static func pitcherLeaders(
        from games: [AttendedGame],
        category: PitcherCategory,
        season: Int? = nil,
        teamID: Int? = nil,
        role: PitcherRoleFilter = .all,
        limit: Int = 20
    ) -> [PlayerAggregate] {
        var rows = aggregates(
            from: games,
            season: season,
            pitchers: true,
            teamID: teamID,
            pitcherRole: role
        )
        applyMVPCounts(&rows, from: games, season: season, pitchers: true)
        rows = rows.filter { category.qualifies($0) }
        return sorted(rows, by: category.value, higherIsBetter: category.higherIsBetter, limit: limit)
    }

    /// Per-game MVPs: best batter line and best pitcher line (when each qualifies).
    /// Batter score ≈ OPS + 0.12×HR + 0.03×RBI; pitcher ≈ IP/K/ER weighting.
    static func gameMVPs(in game: AttendedGame) -> (batter: GamePlayerStat?, pitcher: GamePlayerStat?) {
        let batters = game.playerStats.filter { !$0.isPitcher && ($0.plateAppearances > 0 || $0.atBats > 0) }
        let pitchers = game.playerStats.filter { $0.isPitcher && $0.inningsPitchedOuts > 0 }
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
        pitchers: Bool
    ) {
        let scoped = season.map { year in games.filter { $0.season == year } } ?? games
        var counts: [Int: Int] = [:]
        for game in scoped {
            let pair = gameMVPs(in: game)
            let winner = pitchers ? pair.pitcher : pair.batter
            guard let winner else { continue }
            counts[winner.playerID, default: 0] += 1
        }
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
}
