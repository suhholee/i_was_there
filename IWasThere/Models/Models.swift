import Foundation
import SwiftData

@Model
final class UserProfile {
    var displayName: String
    /// Favorite for MLB diary (Stats API team id).
    var favoriteTeamID: Int?
    var favoriteTeamAbbr: String?
    /// Favorite for KBO diary (synthetic `KBOTeamCatalog` id).
    var favoriteKBOTeamID: Int?
    var favoriteKBOTeamAbbr: String?
    /// `League.rawValue` — which diary Home/Games/Leaders show.
    var activeLeague: String
    var favoritePlayerIDs: [Int]
    /// Min total PA to qualify for Home → Your leaders (batters).
    var homeMinPlateAppearances: Int
    /// Min total batters faced to qualify for Home → Your leaders (pitchers).
    var homeMinBattersFaced: Int
    /// `LeaderboardEngine.BatterCategory.rawValue` for Home / game batter leaders.
    var homeBatterStat: String
    /// `LeaderboardEngine.PitcherCategory.rawValue` for Home / game pitcher leaders.
    var homePitcherStat: String

    init(
        displayName: String = "",
        favoriteTeamID: Int? = nil,
        favoriteTeamAbbr: String? = nil,
        favoriteKBOTeamID: Int? = nil,
        favoriteKBOTeamAbbr: String? = nil,
        activeLeague: String = League.mlb.rawValue,
        favoritePlayerIDs: [Int] = [],
        homeMinPlateAppearances: Int = 0,
        homeMinBattersFaced: Int = 0,
        homeBatterStat: String = LeaderboardEngine.BatterCategory.ops.rawValue,
        homePitcherStat: String = LeaderboardEngine.PitcherCategory.era.rawValue
    ) {
        self.displayName = displayName
        self.favoriteTeamID = favoriteTeamID
        self.favoriteTeamAbbr = favoriteTeamAbbr
        self.favoriteKBOTeamID = favoriteKBOTeamID
        self.favoriteKBOTeamAbbr = favoriteKBOTeamAbbr
        self.activeLeague = activeLeague
        self.favoritePlayerIDs = favoritePlayerIDs
        self.homeMinPlateAppearances = homeMinPlateAppearances
        self.homeMinBattersFaced = homeMinBattersFaced
        self.homeBatterStat = homeBatterStat
        self.homePitcherStat = homePitcherStat
    }

    var league: League {
        get { League(rawValue: activeLeague) ?? .mlb }
        set { activeLeague = newValue.rawValue }
    }

    func favoriteTeamID(for league: League) -> Int? {
        switch league {
        case .mlb: favoriteTeamID
        case .kbo: favoriteKBOTeamID
        }
    }

    func setFavoriteTeam(id: Int?, abbr: String?, for league: League) {
        switch league {
        case .mlb:
            favoriteTeamID = id
            favoriteTeamAbbr = abbr
        case .kbo:
            favoriteKBOTeamID = id
            favoriteKBOTeamAbbr = abbr
        }
    }

    func isFavoritePlayer(_ playerID: Int) -> Bool {
        favoritePlayerIDs.contains(playerID)
    }

    func toggleFavoritePlayer(_ playerID: Int) {
        if let index = favoritePlayerIDs.firstIndex(of: playerID) {
            favoritePlayerIDs.remove(at: index)
        } else {
            favoritePlayerIDs.append(playerID)
        }
    }

    func homeBatterCategory(for league: League) -> LeaderboardEngine.BatterCategory {
        LeaderboardEngine.resolvedBatterCategory(
            rawValue: homeBatterStat,
            league: league
        )
    }

    func homePitcherCategory() -> LeaderboardEngine.PitcherCategory {
        LeaderboardEngine.resolvedPitcherCategory(rawValue: homePitcherStat)
    }

    func setHomeBatterCategory(_ category: LeaderboardEngine.BatterCategory) {
        homeBatterStat = category.rawValue
    }

    func setHomePitcherCategory(_ category: LeaderboardEngine.PitcherCategory) {
        homePitcherStat = category.rawValue
    }
}

@Model
final class AttendedGame {
    @Attribute(.unique) var mlbGamePk: Int
    /// `mlb` or `kbo` — partitions diaries when switching leagues.
    var league: String = League.mlb.rawValue
    /// Stable cross-league key: `mlb:{pk}` or `kbo:{g_id}`.
    var gameKey: String = ""
    /// Sports2i game id when `league == kbo` (e.g. `20250422NCLG0`).
    var kboGameID: String = ""
    /// Calendar day for sorting/display (MLB officialDate as local noon — no TZ day-shift).
    var gameDate: Date
    /// Absolute first pitch; format time in the user's current timezone.
    var firstPitchAt: Date = Date()
    /// MLB slate day `yyyy-MM-dd` (source of truth for the game day).
    var officialDateString: String = ""
    /// Calendar year of the game — used later for season-context filters (WAR, wRC+, etc.).
    var season: Int
    /// MLB `gameType` (`R`, `W`, …) or KBO `sr_id` (`0` = regular season).
    var gameTypeCode: String = ""
    /// KBO Sports2i stadium code (`s_id`); MLB uses `venueName` only.
    var stadiumCode: String = ""
    var venueName: String
    var homeTeamID: Int
    var awayTeamID: Int
    var homeTeamName: String
    var awayTeamName: String
    var homeScore: Int
    var awayScore: Int
    var homeWon: Bool
    var awayWon: Bool
    /// First pitcher listed in the boxscore (usual starter).
    var homeStarterName: String = ""
    var awayStarterName: String = ""
    /// Paid attendance from boxscore `Att` line (nil if unknown).
    var attendanceCount: Int?
    /// Theme night / giveaway (user-entered; not from Stats API).
    var eventTitle: String = ""
    /// Freeform for now; later selectable Friends when accounts exist.
    var companions: String = ""
    var note: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \GamePlayerStat.game)
    var playerStats: [GamePlayerStat]

    @Relationship(deleteRule: .cascade, inverse: \GamePhoto.game)
    var photos: [GamePhoto]

    @Relationship(deleteRule: .cascade, inverse: \GameFriend.game)
    var friends: [GameFriend]

    init(
        mlbGamePk: Int,
        league: League = .mlb,
        gameKey: String = "",
        kboGameID: String = "",
        gameDate: Date,
        firstPitchAt: Date? = nil,
        officialDateString: String = "",
        season: Int,
        gameTypeCode: String = "",
        stadiumCode: String = "",
        venueName: String = "",
        homeTeamID: Int,
        awayTeamID: Int,
        homeTeamName: String,
        awayTeamName: String,
        homeScore: Int,
        awayScore: Int,
        homeWon: Bool = false,
        awayWon: Bool = false,
        homeStarterName: String = "",
        awayStarterName: String = "",
        attendanceCount: Int? = nil,
        eventTitle: String = "",
        companions: String = "",
        note: String = "",
        createdAt: Date = .now,
        playerStats: [GamePlayerStat] = [],
        photos: [GamePhoto] = [],
        friends: [GameFriend] = []
    ) {
        self.mlbGamePk = mlbGamePk
        self.league = league.rawValue
        self.gameKey = gameKey.isEmpty ? LeagueKey.mlb(mlbGamePk) : gameKey
        self.kboGameID = kboGameID
        self.gameDate = gameDate
        self.firstPitchAt = firstPitchAt ?? gameDate
        self.officialDateString = officialDateString
        self.season = season
        self.gameTypeCode = gameTypeCode
        self.stadiumCode = stadiumCode
        self.venueName = venueName
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeWon = homeWon
        self.awayWon = awayWon
        self.homeStarterName = homeStarterName
        self.awayStarterName = awayStarterName
        self.attendanceCount = attendanceCount
        self.eventTitle = eventTitle
        self.companions = companions
        self.note = note
        self.createdAt = createdAt
        self.playerStats = playerStats
        self.photos = photos
        self.friends = friends
    }

    var resolvedLeague: League {
        League(rawValue: league) ?? .mlb
    }

    func ensureGameKey() {
        if gameKey.isEmpty {
            if resolvedLeague == .kbo, !kboGameID.isEmpty {
                gameKey = LeagueKey.kbo(kboGameID)
            } else {
                gameKey = LeagueKey.mlb(mlbGamePk)
            }
        }
        if league.isEmpty {
            league = League.mlb.rawValue
        }
    }
    var attendanceLabel: String? {
        guard let attendanceCount, attendanceCount > 0 else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: attendanceCount)) ?? "\(attendanceCount)"
        return "Attendance: \(formatted)"
    }

    var startersLabel: String {
        let away = awayStarterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let home = homeStarterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let awayPart = away.isEmpty ? "—" : shortPitcherName(away)
        let homePart = home.isEmpty ? "—" : shortPitcherName(home)
        return "\(awayPart) vs \(homePart)"
    }

    private func shortPitcherName(_ full: String) -> String {
        let parts = full.split(separator: " ")
        guard let last = parts.last else { return full }
        if parts.count >= 2, let first = parts.first?.first {
            return "\(first). \(last)"
        }
        return String(last)
    }

    /// Date + first-pitch time in the **device's current timezone**.
    var localDateTimeLabel: String {
        let dateText: String
        if let day = MLBDateParsing.calendarDate(fromOfficial: officialDateString.isEmpty ? nil : officialDateString) {
            dateText = day.formatted(date: .abbreviated, time: .omitted)
        } else {
            dateText = gameDate.formatted(date: .abbreviated, time: .omitted)
        }
        let timeText = firstPitchAt.formatted(date: .omitted, time: .shortened)
        return "\(dateText) · \(timeText)"
    }

    var localDateTimeLabelLong: String {
        let dateText: String
        if let day = MLBDateParsing.calendarDate(fromOfficial: officialDateString.isEmpty ? nil : officialDateString) {
            dateText = day.formatted(date: .complete, time: .omitted)
        } else {
            dateText = gameDate.formatted(date: .complete, time: .omitted)
        }
        let timeText = firstPitchAt.formatted(date: .omitted, time: .shortened)
        return "\(dateText) · \(timeText)"
    }

    /// Whether the user's favorite team won this attended game (Phase 3 Home W%).
    func favoriteTeamWon(favoriteTeamID: Int?) -> Bool? {
        guard let favoriteTeamID else { return nil }
        if homeTeamID == favoriteTeamID { return homeWon }
        if awayTeamID == favoriteTeamID { return awayWon }
        return nil
    }

    /// Winning club’s MLB team ID; `nil` for ties / unknown.
    var winningTeamID: Int? {
        if homeWon && !awayWon { return homeTeamID }
        if awayWon && !homeWon { return awayTeamID }
        if homeScore > awayScore { return homeTeamID }
        if awayScore > homeScore { return awayTeamID }
        return nil
    }

    /// Friend names on this game (structured rows, with legacy `companions` fallback).
    var friendNames: [String] {
        let structured = friends
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !structured.isEmpty { return structured }
        return GameLogFilter.companionTokens(in: companions)
    }

    var friendsLabel: String {
        friendNames.joined(separator: ", ")
    }

    func syncCompanionsFromFriends() {
        companions = friendsLabel
    }
}

@Model
final class GamePlayerStat {
    var playerID: Int
    var playerName: String
    var jerseyNumber: String
    var teamID: Int
    var position: String
    var isPitcher: Bool
    /// Appearance role for pitchers: `SP`, `RP`, `CL` (from boxscore GS/SV).
    var pitcherRole: String = ""

    // Batting counting stats (rates via StatFormulas)
    var atBats: Int
    var hits: Int
    var homeRuns: Int
    var rbi: Int
    var walks: Int
    var hitByPitch: Int
    var sacFlies: Int
    var totalBases: Int
    var plateAppearances: Int
    var doubles: Int
    var triples: Int
    var strikeOutsBatting: Int
    var runs: Int

    // Pitching counting stats
    var inningsPitchedOuts: Int
    var earnedRuns: Int
    var strikeouts: Int
    var hitsAllowed: Int
    var walksAllowed: Int
    var battersFaced: Int
    var pitcherWins: Int
    var pitcherLosses: Int

    var game: AttendedGame?

    init(
        playerID: Int,
        playerName: String,
        jerseyNumber: String = "",
        teamID: Int,
        position: String,
        isPitcher: Bool,
        pitcherRole: String = "",
        atBats: Int = 0,
        hits: Int = 0,
        homeRuns: Int = 0,
        rbi: Int = 0,
        walks: Int = 0,
        hitByPitch: Int = 0,
        sacFlies: Int = 0,
        totalBases: Int = 0,
        plateAppearances: Int = 0,
        doubles: Int = 0,
        triples: Int = 0,
        strikeOutsBatting: Int = 0,
        runs: Int = 0,
        inningsPitchedOuts: Int = 0,
        earnedRuns: Int = 0,
        strikeouts: Int = 0,
        hitsAllowed: Int = 0,
        walksAllowed: Int = 0,
        battersFaced: Int = 0,
        pitcherWins: Int = 0,
        pitcherLosses: Int = 0
    ) {
        self.playerID = playerID
        self.playerName = playerName
        self.jerseyNumber = jerseyNumber
        self.teamID = teamID
        self.position = position
        self.isPitcher = isPitcher
        self.pitcherRole = pitcherRole
        self.atBats = atBats
        self.hits = hits
        self.homeRuns = homeRuns
        self.rbi = rbi
        self.walks = walks
        self.hitByPitch = hitByPitch
        self.sacFlies = sacFlies
        self.totalBases = totalBases
        self.plateAppearances = plateAppearances
        self.doubles = doubles
        self.triples = triples
        self.strikeOutsBatting = strikeOutsBatting
        self.runs = runs
        self.inningsPitchedOuts = inningsPitchedOuts
        self.earnedRuns = earnedRuns
        self.strikeouts = strikeouts
        self.hitsAllowed = hitsAllowed
        self.walksAllowed = walksAllowed
        self.battersFaced = battersFaced
        self.pitcherWins = pitcherWins
        self.pitcherLosses = pitcherLosses
    }

    var battingAverage: Double? {
        StatFormulas.battingAverage(hits: hits, atBats: atBats)
    }

    var onBasePercentage: Double? {
        StatFormulas.onBasePercentage(
            hits: hits,
            walks: walks,
            hitByPitch: hitByPitch,
            atBats: atBats,
            sacFlies: sacFlies
        )
    }

    var slugging: Double? {
        StatFormulas.slugging(totalBases: totalBases, atBats: atBats)
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

    /// Prefer stored role; fall back using starter names on the parent game.
    func resolvedPitcherRole(in game: AttendedGame?) -> String {
        let trimmed = pitcherRole.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed == "SP" || trimmed == "RP" || trimmed == "CL" { return trimmed }
        guard isPitcher, let game else { return trimmed }
        if playerName == game.homeStarterName || playerName == game.awayStarterName {
            return "SP"
        }
        return "RP"
    }
}

@Model
final class GameFriend {
    var name: String
    /// Reserved for a linked #iWasThere account when social sync ships.
    var linkedUserID: Int?
    var game: AttendedGame?

    init(name: String, linkedUserID: Int? = nil) {
        self.name = name
        self.linkedUserID = linkedUserID
    }
}

@Model
final class GamePhoto {
    var relativePath: String
    /// Supabase Storage object path when synced.
    var cloudStoragePath: String = ""
    var createdAt: Date
    var game: AttendedGame?

    init(relativePath: String, cloudStoragePath: String = "", createdAt: Date = .now) {
        self.relativePath = relativePath
        self.cloudStoragePath = cloudStoragePath
        self.createdAt = createdAt
    }
}
