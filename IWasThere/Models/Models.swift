import Foundation
import SwiftData

@Model
final class UserProfile {
    var displayName: String
    var favoriteTeamID: Int?
    var favoriteTeamAbbr: String?
    var favoritePlayerIDs: [Int]

    init(
        displayName: String = "",
        favoriteTeamID: Int? = nil,
        favoriteTeamAbbr: String? = nil,
        favoritePlayerIDs: [Int] = []
    ) {
        self.displayName = displayName
        self.favoriteTeamID = favoriteTeamID
        self.favoriteTeamAbbr = favoriteTeamAbbr
        self.favoritePlayerIDs = favoritePlayerIDs
    }
}

@Model
final class AttendedGame {
    @Attribute(.unique) var mlbGamePk: Int
    /// Calendar day for sorting/display (MLB officialDate as local noon — no TZ day-shift).
    var gameDate: Date
    /// Absolute first pitch; format time in the user's current timezone.
    var firstPitchAt: Date = Date()
    /// MLB slate day `yyyy-MM-dd` (source of truth for the game day).
    var officialDateString: String = ""
    /// Calendar year of the game — used later for season-context filters (WAR, wRC+, etc.).
    var season: Int
    var venueName: String
    var homeTeamID: Int
    var awayTeamID: Int
    var homeTeamName: String
    var awayTeamName: String
    var homeScore: Int
    var awayScore: Int
    var homeWon: Bool
    var awayWon: Bool
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

    init(
        mlbGamePk: Int,
        gameDate: Date,
        firstPitchAt: Date? = nil,
        officialDateString: String = "",
        season: Int,
        venueName: String = "",
        homeTeamID: Int,
        awayTeamID: Int,
        homeTeamName: String,
        awayTeamName: String,
        homeScore: Int,
        awayScore: Int,
        homeWon: Bool = false,
        awayWon: Bool = false,
        eventTitle: String = "",
        companions: String = "",
        note: String = "",
        createdAt: Date = .now,
        playerStats: [GamePlayerStat] = [],
        photos: [GamePhoto] = []
    ) {
        self.mlbGamePk = mlbGamePk
        self.gameDate = gameDate
        self.firstPitchAt = firstPitchAt ?? gameDate
        self.officialDateString = officialDateString
        self.season = season
        self.venueName = venueName
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeWon = homeWon
        self.awayWon = awayWon
        self.eventTitle = eventTitle
        self.companions = companions
        self.note = note
        self.createdAt = createdAt
        self.playerStats = playerStats
        self.photos = photos
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
}

@Model
final class GamePlayerStat {
    var playerID: Int
    var playerName: String
    var jerseyNumber: String
    var teamID: Int
    var position: String
    var isPitcher: Bool

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
        pitcherWins: Int = 0,
        pitcherLosses: Int = 0
    ) {
        self.playerID = playerID
        self.playerName = playerName
        self.jerseyNumber = jerseyNumber
        self.teamID = teamID
        self.position = position
        self.isPitcher = isPitcher
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
}

@Model
final class GamePhoto {
    var relativePath: String
    var createdAt: Date
    var game: AttendedGame?

    init(relativePath: String, createdAt: Date = .now) {
        self.relativePath = relativePath
        self.createdAt = createdAt
    }
}
