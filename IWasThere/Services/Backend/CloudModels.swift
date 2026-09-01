import Foundation

// MARK: - Cloud rows (user-owned fields only)

struct CloudProfileRow: Codable, Sendable {
    let userId: UUID
    var displayName: String
    var favoriteTeamId: Int?
    var favoriteTeamAbbr: String?
    var favoriteKboTeamId: Int?
    var favoriteKboTeamAbbr: String?
    var activeLeague: String
    var favoritePlayerIds: [Int]
    var homeMinPlateAppearances: Int
    var homeMinBattersFaced: Int
    var homeBatterStat: String?
    var homePitcherStat: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case favoriteTeamId = "favorite_team_id"
        case favoriteTeamAbbr = "favorite_team_abbr"
        case favoriteKboTeamId = "favorite_kbo_team_id"
        case favoriteKboTeamAbbr = "favorite_kbo_team_abbr"
        case activeLeague = "active_league"
        case favoritePlayerIds = "favorite_player_ids"
        case homeMinPlateAppearances = "home_min_plate_appearances"
        case homeMinBattersFaced = "home_min_batters_faced"
        case homeBatterStat = "home_batter_stat"
        case homePitcherStat = "home_pitcher_stat"
        case updatedAt = "updated_at"
    }
}

struct CloudAttendedGameRow: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let gameKey: String
    let league: String
    let mlbGamePk: Int
    let kboGameId: String
    let kboGDt: String
    let officialDateString: String
    let gameDate: Date
    let season: Int
    var eventTitle: String
    var note: String
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gameKey = "game_key"
        case league
        case mlbGamePk = "mlb_game_pk"
        case kboGameId = "kbo_game_id"
        case kboGDt = "kbo_g_dt"
        case officialDateString = "official_date_string"
        case gameDate = "game_date"
        case season
        case eventTitle = "event_title"
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CloudGameFriendRow: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let gameId: UUID
    let name: String
    let linkedUserId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gameId = "game_id"
        case name
        case linkedUserId = "linked_user_id"
    }
}

struct CloudGamePhotoRow: Codable, Sendable, Identifiable {
    let id: UUID
    let userId: UUID
    let gameId: UUID
    let storagePath: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gameId = "game_id"
        case storagePath = "storage_path"
        case createdAt = "created_at"
    }
}

// MARK: - Upsert payloads (omit server-generated ids on insert)

struct CloudProfileUpsert: Codable, Sendable {
    let userId: UUID
    var displayName: String
    var favoriteTeamId: Int?
    var favoriteTeamAbbr: String?
    var favoriteKboTeamId: Int?
    var favoriteKboTeamAbbr: String?
    var activeLeague: String
    var favoritePlayerIds: [Int]
    var homeMinPlateAppearances: Int
    var homeMinBattersFaced: Int
    var homeBatterStat: String
    var homePitcherStat: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case favoriteTeamId = "favorite_team_id"
        case favoriteTeamAbbr = "favorite_team_abbr"
        case favoriteKboTeamId = "favorite_kbo_team_id"
        case favoriteKboTeamAbbr = "favorite_kbo_team_abbr"
        case activeLeague = "active_league"
        case favoritePlayerIds = "favorite_player_ids"
        case homeMinPlateAppearances = "home_min_plate_appearances"
        case homeMinBattersFaced = "home_min_batters_faced"
        case homeBatterStat = "home_batter_stat"
        case homePitcherStat = "home_pitcher_stat"
        case updatedAt = "updated_at"
    }
}

struct CloudAttendedGameUpsert: Codable, Sendable {
    let userId: UUID
    let gameKey: String
    let league: String
    let mlbGamePk: Int
    let kboGameId: String
    let kboGDt: String
    let officialDateString: String
    let gameDate: String
    let season: Int
    var eventTitle: String
    var note: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case gameKey = "game_key"
        case league
        case mlbGamePk = "mlb_game_pk"
        case kboGameId = "kbo_game_id"
        case kboGDt = "kbo_g_dt"
        case officialDateString = "official_date_string"
        case gameDate = "game_date"
        case season
        case eventTitle = "event_title"
        case note
        case updatedAt = "updated_at"
    }
}

struct CloudGameFriendInsert: Codable, Sendable {
    let userId: UUID
    let gameId: UUID
    let name: String
}

struct CloudGamePhotoInsert: Codable, Sendable {
    let userId: UUID
    let gameId: UUID
    let storagePath: String
}

enum CloudDateCodec {
    static let postgres: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func string(from date: Date) -> String {
        postgres.string(from: date)
    }
}

extension CloudProfileRow {
    func apply(to profile: UserProfile) {
        profile.displayName = displayName
        profile.favoriteTeamID = favoriteTeamId
        profile.favoriteTeamAbbr = favoriteTeamAbbr
        profile.favoriteKBOTeamID = favoriteKboTeamId
        profile.favoriteKBOTeamAbbr = favoriteKboTeamAbbr
        profile.activeLeague = activeLeague
        profile.favoritePlayerIDs = favoritePlayerIds
        profile.homeMinPlateAppearances = homeMinPlateAppearances
        profile.homeMinBattersFaced = homeMinBattersFaced
        profile.homeBatterStat = homeBatterStat
            ?? LeaderboardEngine.BatterCategory.ops.rawValue
        profile.homePitcherStat = homePitcherStat
            ?? LeaderboardEngine.PitcherCategory.era.rawValue
    }
}

extension CloudProfileUpsert {
    static func from(profile: UserProfile, userId: UUID) -> CloudProfileUpsert {
        CloudProfileUpsert(
            userId: userId,
            displayName: profile.displayName,
            favoriteTeamId: profile.favoriteTeamID,
            favoriteTeamAbbr: profile.favoriteTeamAbbr,
            favoriteKboTeamId: profile.favoriteKBOTeamID,
            favoriteKboTeamAbbr: profile.favoriteKBOTeamAbbr,
            activeLeague: profile.activeLeague,
            favoritePlayerIds: profile.favoritePlayerIDs,
            homeMinPlateAppearances: profile.homeMinPlateAppearances,
            homeMinBattersFaced: profile.homeMinBattersFaced,
            homeBatterStat: profile.homeBatterStat,
            homePitcherStat: profile.homePitcherStat,
            updatedAt: CloudDateCodec.string(from: .now)
        )
    }
}

extension CloudAttendedGameUpsert {
    static func from(game: AttendedGame, userId: UUID) -> CloudAttendedGameUpsert {
        let kboGDt: String
        if game.resolvedLeague == .kbo, !game.kboGameID.isEmpty {
            kboGDt = Self.kboGDt(from: game)
        } else {
            kboGDt = ""
        }
        return CloudAttendedGameUpsert(
            userId: userId,
            gameKey: game.gameKey,
            league: game.league,
            mlbGamePk: game.mlbGamePk,
            kboGameId: game.kboGameID,
            kboGDt: kboGDt,
            officialDateString: game.officialDateString,
            gameDate: CloudDateCodec.string(from: game.gameDate),
            season: game.season,
            eventTitle: game.eventTitle,
            note: game.note,
            updatedAt: CloudDateCodec.string(from: .now)
        )
    }

    /// Reconstruct Sports2i `g_dt` (`yyyyMMdd`) from stored game date / id.
    private static func kboGDt(from game: AttendedGame) -> String {
        if game.officialDateString.count == 10 {
            return game.officialDateString.replacingOccurrences(of: "-", with: "")
        }
        let cal = Calendar.current
        let y = cal.component(.year, from: game.gameDate)
        let m = cal.component(.month, from: game.gameDate)
        let d = cal.component(.day, from: game.gameDate)
        return String(format: "%04d%02d%02d", y, m, d)
    }
}
