import Foundation

struct GameFriendFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let chipLabel: String
    let linkedUserId: UUID?
    let matchName: String?

    static let anyone = GameFriendFilterOption(
        id: "anyone",
        chipLabel: "Anyone",
        linkedUserId: nil,
        matchName: nil
    )

    var isActive: Bool {
        self != .anyone
    }

    init(id: String, chipLabel: String, linkedUserId: UUID?, matchName: String?) {
        self.id = id
        self.chipLabel = chipLabel
        self.linkedUserId = linkedUserId
        self.matchName = matchName
    }

    init(friend: UserSearchResult) {
        let displayName = friend.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: friend.userId.uuidString,
            chipLabel: friend.usernameTag,
            linkedUserId: friend.userId,
            matchName: displayName.isEmpty ? friend.username : displayName
        )
    }
}

struct RankedMutualFriend: Identifiable, Sendable {
    let friend: UserSearchResult
    let gamesTogether: Int
    let togetherAttendance: LeaderboardEngine.AttendanceRecord

    var id: UUID { friend.userId }
}

enum FriendListRankMode: String, CaseIterable, Identifiable {
    case gamesTogether
    case winRate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gamesTogether: "Most games"
        case .winRate: "Win rate"
        }
    }
}

enum FriendRankMedal: Int {
    case gold = 1
    case silver = 2
    case bronze = 3

    var systemImage: String { "medal.fill" }

    var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .gold: (1.0, 0.78, 0.0)
        case .silver: (0.78, 0.8, 0.84)
        case .bronze: (0.8, 0.5, 0.2)
        }
    }

    static func forRank(_ rank: Int) -> FriendRankMedal? {
        FriendRankMedal(rawValue: rank)
    }
}

enum GamePhaseFilter: String, CaseIterable, Identifiable {
    case all
    case regularSeason
    case postseason

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All games"
        case .regularSeason: "Regular season"
        case .postseason: "Postseason"
        }
    }
}

enum FavoriteResultFilter: String, CaseIterable, Identifiable {
    case all
    case wins
    case losses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All results"
        case .wins: "My team W"
        case .losses: "My team L"
        }
    }
}

enum GameLogFilter {
    static func apply(
        to games: [AttendedGame],
        season: Int?,
        teamID: Int?,
        phase: GamePhaseFilter,
        venue: String?,
        favoriteResult: FavoriteResultFilter,
        favoriteTeamID: Int?,
        friend: GameFriendFilterOption?
    ) -> [AttendedGame] {
        games.filter { game in
            if let season, game.season != season { return false }
            if let teamID, game.homeTeamID != teamID && game.awayTeamID != teamID { return false }
            if !matchesPhase(game, phase: phase) { return false }
            if let venue, !venue.isEmpty, game.resolvedVenueName != venue { return false }
            if !matchesFavoriteResult(game, filter: favoriteResult, favoriteTeamID: favoriteTeamID) {
                return false
            }
            if let friend, friend.isActive, !matchesFriend(game, filter: friend) {
                return false
            }
            return true
        }
    }

    static func seasons(in games: [AttendedGame]) -> [Int] {
        Array(Set(games.map(\.season))).sorted(by: >)
    }

    static func teams(
        in games: [AttendedGame],
        league: League,
        favoriteTeamID: Int?
    ) -> [GameFilterTeam] {
        var seen = Set<Int>()
        var result: [GameFilterTeam] = []
        for game in games {
            for id in [game.homeTeamID, game.awayTeamID] {
                guard seen.insert(id).inserted else { continue }
                let name: String
                switch league {
                case .mlb:
                    name = MLBTeamCatalog.team(id: id)?.name
                        ?? (game.homeTeamID == id ? game.homeTeamName : game.awayTeamName)
                case .kbo:
                    name = KBOTeamCatalog.team(id: id)?.name
                        ?? (game.homeTeamID == id ? game.homeTeamName : game.awayTeamName)
                }
                result.append(GameFilterTeam(id: id, name: name))
            }
        }
        return result.sorted { lhs, rhs in
            if let favoriteTeamID {
                if lhs.id == favoriteTeamID { return true }
                if rhs.id == favoriteTeamID { return false }
            }
            return lhs.name < rhs.name
        }
    }

    static func venues(in games: [AttendedGame]) -> [String] {
        Array(Set(games.map(\.resolvedVenueName).filter { !$0.isEmpty })).sorted()
    }

    static func friends(in games: [AttendedGame]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for game in games {
            for name in game.friendNames {
                let key = name.lowercased()
                guard seen.insert(key).inserted else { continue }
                result.append(name)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func friendFilterOptions(
        mutualFriends: [UserSearchResult],
        games: [AttendedGame]
    ) -> [GameFriendFilterOption] {
        var options: [GameFriendFilterOption] = mutualFriends.map(GameFriendFilterOption.init(friend:))
        var coveredKeys = Set(options.compactMap { $0.matchName?.lowercased() })
        coveredKeys.formUnion(mutualFriends.map { $0.username.lowercased() })
        coveredKeys.formUnion(mutualFriends.map { "@\($0.username)".lowercased() })

        for name in friends(in: games) {
            let key = name.lowercased()
            guard !coveredKeys.contains(key) else { continue }
            coveredKeys.insert(key)
            options.append(
                GameFriendFilterOption(
                    id: "name:\(key)",
                    chipLabel: name,
                    linkedUserId: nil,
                    matchName: name
                )
            )
        }
        return options
    }

    /// Legacy helper for importing old comma-separated companion strings.
    static func companions(in games: [AttendedGame]) -> [String] {
        friends(in: games)
    }

    static func gamesTogether(with friend: UserSearchResult, in games: [AttendedGame]) -> [AttendedGame] {
        games.filter { gameIncludes(friend, in: $0) }
    }

    static func gamesTogetherCount(with friend: UserSearchResult, in games: [AttendedGame]) -> Int {
        gamesTogether(with: friend, in: games).count
    }

    static func rankMutualFriends(
        _ friends: [UserSearchResult],
        games: [AttendedGame],
        mlbFavoriteTeamID: Int?,
        kboFavoriteTeamID: Int?,
        mode: FriendListRankMode
    ) -> [RankedMutualFriend] {
        friends
            .map { friend in
                let togetherGames = gamesTogether(with: friend, in: games)
                return RankedMutualFriend(
                    friend: friend,
                    gamesTogether: togetherGames.count,
                    togetherAttendance: LeaderboardEngine.favoriteAttendanceTogether(
                        games: togetherGames,
                        mlbFavoriteTeamID: mlbFavoriteTeamID,
                        kboFavoriteTeamID: kboFavoriteTeamID
                    )
                )
            }
            .sorted { lhs, rhs in
                switch mode {
                case .gamesTogether:
                    if lhs.gamesTogether != rhs.gamesTogether {
                        return lhs.gamesTogether > rhs.gamesTogether
                    }
                case .winRate:
                    let leftPct = lhs.togetherAttendance.winPercentage
                    let rightPct = rhs.togetherAttendance.winPercentage
                    switch (leftPct, rightPct) {
                    case let (left?, right?) where left != right:
                        return left > right
                    case (nil, .some):
                        return false
                    case (.some, nil):
                        return true
                    default:
                        if lhs.togetherAttendance.games != rhs.togetherAttendance.games {
                            return lhs.togetherAttendance.games > rhs.togetherAttendance.games
                        }
                        if lhs.gamesTogether != rhs.gamesTogether {
                            return lhs.gamesTogether > rhs.gamesTogether
                        }
                    }
                }
                return friendName(lhs.friend).localizedCaseInsensitiveCompare(friendName(rhs.friend)) == .orderedAscending
            }
    }

    private static func friendName(_ friend: UserSearchResult) -> String {
        friend.displayName.isEmpty ? friend.username : friend.displayName
    }

    private static func gameIncludes(_ friend: UserSearchResult, in game: AttendedGame) -> Bool {
        game.friends.contains { gameFriend in
            if let linkedUserId = gameFriend.resolvedLinkedUserId {
                return linkedUserId == friend.userId
            }
            let name = gameFriend.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return false }
            let display = friend.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty,
               name.localizedCaseInsensitiveCompare(display) == .orderedSame {
                return true
            }
            let username = friend.username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !username.isEmpty,
               name.localizedCaseInsensitiveCompare(username) == .orderedSame {
                return true
            }
            return false
        }
    }

    static func companionTokens(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: " & ", with: ",")
            .replacingOccurrences(of: " and ", with: ",", options: .caseInsensitive)
        return normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func matchesPhase(_ game: AttendedGame, phase: GamePhaseFilter) -> Bool {
        switch phase {
        case .all: return true
        case .regularSeason: return game.isRegularSeasonGame
        case .postseason: return game.isPostseasonGame
        }
    }

    private static func matchesFavoriteResult(
        _ game: AttendedGame,
        filter: FavoriteResultFilter,
        favoriteTeamID: Int?
    ) -> Bool {
        switch filter {
        case .all: return true
        case .wins: return game.favoriteTeamWon(favoriteTeamID: favoriteTeamID) == true
        case .losses: return game.favoriteTeamWon(favoriteTeamID: favoriteTeamID) == false
        }
    }

    private static func matchesFriend(_ game: AttendedGame, filter: GameFriendFilterOption) -> Bool {
        game.friends.contains { gameFriend in
            if let linkedUserId = filter.linkedUserId,
               gameFriend.resolvedLinkedUserId == linkedUserId {
                return true
            }
            if let matchName = filter.matchName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !matchName.isEmpty {
                let name = gameFriend.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.localizedCaseInsensitiveCompare(matchName) == .orderedSame {
                    return true
                }
            }
            return false
        }
    }
}

extension AttendedGame {
    /// MLB `gameType` (`R`, `W`, …) or KBO `sr_id` (`0` = regular season).
    var resolvedVenueName: String {
        switch resolvedLeague {
        case .kbo:
            return KBOStadiumCatalog.canonicalName(
                stadiumCode: stadiumCode,
                storedVenueName: venueName,
                homeTeamID: homeTeamID
            )
        case .mlb:
            return venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var isRegularSeasonGame: Bool {
        switch resolvedLeague {
        case .mlb:
            let code = gameTypeCode.uppercased()
            return code.isEmpty || code == "R"
        case .kbo:
            return gameTypeCode.isEmpty || gameTypeCode == "0"
        }
    }

    var isPostseasonGame: Bool {
        switch resolvedLeague {
        case .mlb:
            let code = gameTypeCode.uppercased()
            return ["F", "D", "L", "W", "P", "C"].contains(code)
        case .kbo:
            return !gameTypeCode.isEmpty && gameTypeCode != "0"
        }
    }

    var gamePhaseShortLabel: String? {
        if isPostseasonGame { return "Postseason" }
        if isRegularSeasonGame { return nil }
        let code = gameTypeCode.uppercased()
        if code.isEmpty { return nil }
        switch resolvedLeague {
        case .mlb: return MLBGameTypeCatalog.label(for: code)
        case .kbo: return "Postseason"
        }
    }
}

enum MLBGameTypeCatalog {
    static func label(for code: String) -> String {
        switch code.uppercased() {
        case "R": return "Regular season"
        case "S": return "Spring training"
        case "F": return "Wild Card"
        case "D": return "Division Series"
        case "L": return "LCS"
        case "W": return "World Series"
        case "P": return "Postseason"
        case "C": return "Championship"
        case "A": return "All-Star"
        case "E": return "Exhibition"
        default: return code
        }
    }
}
