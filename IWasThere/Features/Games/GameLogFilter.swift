import Foundation

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
        friend: String?
    ) -> [AttendedGame] {
        games.filter { game in
            if let season, game.season != season { return false }
            if let teamID, game.homeTeamID != teamID && game.awayTeamID != teamID { return false }
            if !matchesPhase(game, phase: phase) { return false }
            if let venue, !venue.isEmpty, game.resolvedVenueName != venue { return false }
            if !matchesFavoriteResult(game, filter: favoriteResult, favoriteTeamID: favoriteTeamID) {
                return false
            }
            if let friend, !friend.isEmpty, !matchesFriend(game, filter: friend) {
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

    /// Legacy helper for importing old comma-separated companion strings.
    static func companions(in games: [AttendedGame]) -> [String] {
        friends(in: games)
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

    private static func matchesFriend(_ game: AttendedGame, filter: String) -> Bool {
        game.friendNames.contains { $0.localizedCaseInsensitiveCompare(filter) == .orderedSame }
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
