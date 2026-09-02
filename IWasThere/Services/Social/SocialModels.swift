import Foundation

struct UserSearchResult: Codable, Identifiable, Sendable, Hashable {
    let userId: UUID
    let username: String
    let displayName: String
    let avatarStoragePath: String?
    let profileVisibility: String
    let favoriteTeamId: Int?
    let favoriteTeamAbbr: String?
    let favoriteKboTeamId: Int?
    let favoriteKboTeamAbbr: String?
    let activeLeague: String

    var id: UUID { userId }

    var visibility: ProfileVisibility {
        ProfileVisibility(rawValue: profileVisibility) ?? .public
    }

    var usernameTag: String {
        username.isEmpty ? "" : "@\(username)"
    }

    init(profile: PublicUserProfile) {
        self.userId = profile.userId
        self.username = profile.username
        self.displayName = profile.displayName
        self.avatarStoragePath = profile.avatarStoragePath
        self.profileVisibility = profile.profileVisibility
        self.favoriteTeamId = profile.favoriteTeamId
        self.favoriteTeamAbbr = profile.favoriteTeamAbbr
        self.favoriteKboTeamId = profile.favoriteKboTeamId
        self.favoriteKboTeamAbbr = profile.favoriteKboTeamAbbr
        self.activeLeague = profile.activeLeague
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarStoragePath = "avatar_storage_path"
        case profileVisibility = "profile_visibility"
        case favoriteTeamId = "favorite_team_id"
        case favoriteTeamAbbr = "favorite_team_abbr"
        case favoriteKboTeamId = "favorite_kbo_team_id"
        case favoriteKboTeamAbbr = "favorite_kbo_team_abbr"
        case activeLeague = "active_league"
    }
}

struct PublicUserProfile: Codable, Identifiable, Sendable, Hashable {
    let userId: UUID
    let username: String
    let displayName: String
    let avatarStoragePath: String?
    let profileVisibility: String
    let favoriteTeamId: Int?
    let favoriteTeamAbbr: String?
    let favoriteKboTeamId: Int?
    let favoriteKboTeamAbbr: String?
    let activeLeague: String
    let favoritePlayerIds: [Int]
    let favoritePlayerMetaJSON: String?
    let canViewGames: Bool
    let followStatus: String?

    var id: UUID { userId }

    var visibility: ProfileVisibility {
        ProfileVisibility(rawValue: profileVisibility) ?? .public
    }

    var relationship: FollowRelationshipStatus {
        FollowRelationshipStatus(rawValue: followStatus ?? "none") ?? .none
    }

    var league: League {
        League(rawValue: activeLeague) ?? .mlb
    }

    var usernameTag: String {
        username.isEmpty ? "" : "@\(username)"
    }

    func favoriteTeamID(for league: League) -> Int? {
        switch league {
        case .mlb: favoriteTeamId
        case .kbo: favoriteKboTeamId
        }
    }

    func favoritePlayerMetaByID() -> [Int: FavoritePlayerMeta] {
        guard let favoritePlayerMetaJSON,
              let data = favoritePlayerMetaJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([FavoritePlayerMeta].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.playerID, $0) })
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarStoragePath = "avatar_storage_path"
        case profileVisibility = "profile_visibility"
        case favoriteTeamId = "favorite_team_id"
        case favoriteTeamAbbr = "favorite_team_abbr"
        case favoriteKboTeamId = "favorite_kbo_team_id"
        case favoriteKboTeamAbbr = "favorite_kbo_team_abbr"
        case activeLeague = "active_league"
        case favoritePlayerIds = "favorite_player_ids"
        case favoritePlayerMetaJSON = "favorite_player_meta_json"
        case canViewGames = "can_view_games"
        case followStatus = "follow_status"
    }
}

enum FollowRelationshipStatus: String, Codable, Sendable, Hashable {
    case none
    case selfProfile = "self"
    case mutual
    case outgoingPending = "outgoing_pending"
    case incomingPending = "incoming_pending"
}

struct IncomingFollowRequest: Codable, Identifiable, Sendable, Hashable {
    let requestId: UUID
    let requesterUserId: UUID
    let username: String
    let displayName: String
    let avatarStoragePath: String?
    let createdAt: Date

    var id: UUID { requestId }

    var usernameTag: String {
        username.isEmpty ? "" : "@\(username)"
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case requesterUserId = "requester_user_id"
        case username
        case displayName = "display_name"
        case avatarStoragePath = "avatar_storage_path"
        case createdAt = "created_at"
    }
}

struct RemoteGameFriendRow: Codable, Sendable {
    let name: String
}

struct RemoteGamePhotoRow: Codable, Sendable {
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
    }
}

struct IncomingGameInvite: Codable, Identifiable, Sendable, Hashable {
    let inviteId: UUID
    let fromUserId: UUID
    let username: String
    let displayName: String
    let avatarStoragePath: String?
    let gameKey: String
    let league: String
    let gameDate: Date
    let officialDateString: String?
    let awayTeamName: String?
    let homeTeamName: String?
    let eventTitle: String

    var id: UUID { inviteId }

    var usernameTag: String {
        username.isEmpty ? "" : "@\(username)"
    }

    var senderLabel: String {
        displayName.isEmpty ? usernameTag : displayName
    }

    var matchupLabel: String {
        let away = (awayTeamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let home = (homeTeamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !away.isEmpty, !home.isEmpty else { return "" }
        return "\(away) @ \(home)"
    }

    var inviteDateLabel: String {
        let official = officialDateString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let day = MLBDateParsing.calendarDate(fromOfficial: official.isEmpty ? nil : official) {
            return day.formatted(date: .abbreviated, time: .omitted)
        }
        return gameDate.formatted(date: .abbreviated, time: .omitted)
    }

    var gameDetailSubtitle: String {
        [inviteDateLabel, matchupLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case fromUserId = "from_user_id"
        case username
        case displayName = "display_name"
        case avatarStoragePath = "avatar_storage_path"
        case gameKey = "game_key"
        case league
        case gameDate = "game_date"
        case officialDateString = "official_date_string"
        case awayTeamName = "away_team_name"
        case homeTeamName = "home_team_name"
        case eventTitle = "event_title"
    }
}

struct GameLeftNotification: Codable, Identifiable, Sendable, Hashable {
    let notificationId: UUID
    let actorUserId: UUID
    let username: String
    let displayName: String
    let avatarStoragePath: String?
    let gameKey: String
    let league: String
    let gameDate: Date
    let officialDateString: String?
    let awayTeamName: String?
    let homeTeamName: String?
    let createdAt: Date

    var id: UUID { notificationId }

    var usernameTag: String {
        username.isEmpty ? "" : "@\(username)"
    }

    var actorLabel: String {
        displayName.isEmpty ? usernameTag : displayName
    }

    var matchupLabel: String {
        let away = (awayTeamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let home = (homeTeamName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !away.isEmpty, !home.isEmpty else { return "" }
        return "\(away) @ \(home)"
    }

    var gameDateLabel: String {
        let official = officialDateString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let day = MLBDateParsing.calendarDate(fromOfficial: official.isEmpty ? nil : official) {
            return day.formatted(date: .abbreviated, time: .omitted)
        }
        return gameDate.formatted(date: .abbreviated, time: .omitted)
    }

    var gameDetailSubtitle: String {
        [gameDateLabel, matchupLabel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case notificationId = "notification_id"
        case actorUserId = "actor_user_id"
        case username
        case displayName = "display_name"
        case avatarStoragePath = "avatar_storage_path"
        case gameKey = "game_key"
        case league
        case gameDate = "game_date"
        case officialDateString = "official_date_string"
        case awayTeamName = "away_team_name"
        case homeTeamName = "home_team_name"
        case createdAt = "created_at"
    }
}
