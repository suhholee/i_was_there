import Foundation

/// Thin client for the public MLB Stats API (`https://statsapi.mlb.com/api`).
actor MLBClient {
    static let shared = MLBClient()

    private let session: URLSession
    private let baseURL = URL(string: "https://statsapi.mlb.com/api/v1")!
    private let userAgent = "IWasThere/0.1 (prototype; local-first)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func schedule(date: Date) async throws -> MLBScheduleResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("schedule"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "sportId", value: "1"),
            URLQueryItem(name: "date", value: MLBDateParsing.scheduleQueryDate(from: date))
        ]
        return try await get(components.url!)
    }

    func boxscore(gamePk: Int) async throws -> MLBBoxscoreResponse {
        let url = baseURL.appendingPathComponent("game/\(gamePk)/boxscore")
        return try await get(url)
    }

    /// Locate a schedule row for hydration after cloud restore.
    func findScheduleGame(gamePk: Int, around date: Date) async throws -> MLBScheduleGame {
        let response = try await schedule(date: date)
        if let match = response.dates.flatMap(\.games).first(where: { $0.gamePk == gamePk }) {
            return match
        }
        // Fallback: day before / after (rare timezone edge cases).
        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: date),
           let match = try await schedule(date: prev).dates.flatMap(\.games).first(where: { $0.gamePk == gamePk }) {
            return match
        }
        if let next = Calendar.current.date(byAdding: .day, value: 1, to: date),
           let match = try await schedule(date: next).dates.flatMap(\.games).first(where: { $0.gamePk == gamePk }) {
            return match
        }
        throw MLBClientError.gameNotFound(gamePk)
    }

    func standings(season: Int, leagueIDs: String = "103,104") async throws -> MLBStandingsResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("standings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "leagueId", value: leagueIDs),
            URLQueryItem(name: "season", value: String(season))
        ]
        return try await get(components.url!)
    }

    func person(id: Int) async throws -> MLBPersonDetail {
        let url = baseURL.appendingPathComponent("people/\(id)")
        let response: MLBPeopleResponse = try await get(url)
        guard let person = response.people.first else {
            throw MLBClientError.badStatus(404)
        }
        return person
    }

    func teamRoster(teamID: Int, rosterType: String = "active") async throws -> [MLBRosterEntry] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("teams/\(teamID)/roster"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "rosterType", value: rosterType)]
        let response: MLBRosterResponse = try await get(components.url!)
        return response.roster
    }

    /// Season / career lines from Stats API. Current season is season-to-date when asked for this year.
    func playerStats(
        personID: Int,
        group: MLBStatGroup,
        type: MLBStatType = .yearByYear
    ) async throws -> [MLBSeasonSplit] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("people/\(personID)/stats"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "stats", value: type.rawValue),
            URLQueryItem(name: "group", value: group.rawValue),
            URLQueryItem(name: "sportId", value: "1")
        ]
        let response: MLBPlayerStatsResponse = try await get(components.url!)
        return response.stats.first?.splits ?? []
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MLBClientError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MLBClientError.decode(error)
        }
    }
}

enum MLBClientError: Error {
    case badStatus(Int)
    case decode(Error)
    case gameNotFound(Int)
}

// MARK: - DTOs (subset used by Phase 0/1)

struct MLBScheduleResponse: Decodable {
    let dates: [MLBScheduleDate]
}

struct MLBScheduleDate: Decodable {
    let date: String
    let games: [MLBScheduleGame]
}

struct MLBScheduleGame: Decodable {
    let gamePk: Int
    let officialDate: String?
    /// Absolute first-pitch instant from MLB (ISO8601), e.g. `2024-10-26T00:08:00Z`.
    let gameDate: String?
    let gameType: String?
    let status: MLBGameStatus
    let teams: MLBScheduleTeams
    let venue: MLBVenue?
}

struct MLBGameStatus: Decodable {
    let detailedState: String
    let abstractGameState: String?
}

struct MLBScheduleTeams: Decodable {
    let away: MLBScheduleTeamSide
    let home: MLBScheduleTeamSide
}

struct MLBScheduleTeamSide: Decodable {
    let team: MLBTeamRef
    let score: Int?
    let isWinner: Bool?
}

struct MLBTeamRef: Decodable {
    let id: Int
    let name: String
}

struct MLBVenue: Decodable {
    let id: Int?
    let name: String?
}

struct MLBBoxscoreResponse: Decodable {
    let teams: MLBBoxscoreTeams
    /// Boxscore footer lines (WP, weather, **Att**, venue, …).
    let info: [MLBBoxscoreInfoLine]?
}

struct MLBBoxscoreInfoLine: Decodable {
    let label: String?
    let value: String?
}

struct MLBBoxscoreTeams: Decodable {
    let away: MLBBoxscoreTeam
    let home: MLBBoxscoreTeam
}

struct MLBBoxscoreTeam: Decodable {
    let team: MLBTeamRef
    let batters: [Int]
    let pitchers: [Int]
    let players: [String: MLBBoxscorePlayer]
}

struct MLBBoxscorePlayer: Decodable {
    let person: MLBPerson
    let jerseyNumber: String?
    let position: MLBPosition?
    let stats: MLBPlayerStatBlock?
}

struct MLBPerson: Decodable {
    let id: Int
    let fullName: String
}

struct MLBPosition: Decodable {
    let abbreviation: String?
}

struct MLBPlayerStatBlock: Decodable {
    let batting: MLBBattingStats?
    let pitching: MLBPitchingStats?
}

struct MLBBattingStats: Decodable {
    let atBats: Int?
    let hits: Int?
    let homeRuns: Int?
    let rbi: Int?
    let baseOnBalls: Int?
    let hitByPitch: Int?
    let sacFlies: Int?
    let totalBases: Int?
    let plateAppearances: Int?
    let doubles: Int?
    let triples: Int?
    let strikeOuts: Int?
    let runs: Int?
    // Game lines often omit rate stats; we compute AVG/OPS from counting stats.
    let avg: String?
    let ops: String?
}

struct MLBPitchingStats: Decodable {
    let inningsPitched: String?
    let outs: Int?
    let earnedRuns: Int?
    let strikeOuts: Int?
    let hits: Int?
    let baseOnBalls: Int?
    let wins: Int?
    let losses: Int?
    let gamesStarted: Int?
    let saves: Int?
    let battersFaced: Int?
    let era: String?
    let whip: String?
    let note: String?
}

struct MLBStandingsResponse: Decodable {
    let records: [MLBStandingsDivision]
}

struct MLBStandingsDivision: Decodable {
    let teamRecords: [MLBTeamRecord]
}

struct MLBTeamRecord: Decodable {
    let team: MLBTeamRef
    let wins: Int
    let losses: Int
    let winningPercentage: String
}

enum MLBStatGroup: String {
    case hitting
    case pitching
}

enum MLBStatType: String {
    case yearByYear
    case season
}

struct MLBPeopleResponse: Decodable {
    let people: [MLBPersonDetail]
}

struct MLBRosterResponse: Decodable {
    let roster: [MLBRosterEntry]
}

struct MLBRosterEntry: Decodable {
    let person: MLBRosterPerson
    let jerseyNumber: String?
    let position: MLBPosition?
}

struct MLBRosterPerson: Decodable {
    let id: Int
    let fullName: String
}

struct MLBPersonDetail: Decodable {
    let id: Int
    let fullName: String
    let primaryNumber: String?
    let currentTeam: MLBTeamRef?
    let primaryPosition: MLBPosition?
    let batSide: MLBCodeName?
    let pitchHand: MLBCodeName?
    let birthDate: String?
    let height: String?
    let weight: Int?
}

struct MLBCodeName: Decodable {
    let code: String?
    let description: String?
}

struct MLBPlayerStatsResponse: Decodable {
    let stats: [MLBPlayerStatsBlock]
}

struct MLBPlayerStatsBlock: Decodable {
    let splits: [MLBSeasonSplit]
}

struct MLBSeasonSplit: Decodable, Identifiable {
    var id: String { "\(season ?? "x")-\(stat.gamesPlayed ?? 0)-\(stat.atBats ?? 0)-\(stat.inningsPitched ?? "")" }

    let season: String?
    let stat: MLBSeasonStatLine
    let team: MLBTeamRef?
}

struct MLBSeasonStatLine: Decodable {
    let gamesPlayed: Int?
    let avg: String?
    let obp: String?
    let slg: String?
    let ops: String?
    let atBats: Int?
    let hits: Int?
    let doubles: Int?
    let triples: Int?
    let homeRuns: Int?
    let rbi: Int?
    let baseOnBalls: Int?
    let strikeOuts: Int?
    let hitByPitch: Int?
    let sacFlies: Int?
    let totalBases: Int?
    let runs: Int?
    let plateAppearances: Int?

    let era: String?
    let whip: String?
    let inningsPitched: String?
    let earnedRuns: Int?
    let wins: Int?
    let losses: Int?
    let gamesStarted: Int?
    let saves: Int?
}
