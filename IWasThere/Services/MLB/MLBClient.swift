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

    func standings(season: Int, leagueIDs: String = "103,104") async throws -> MLBStandingsResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("standings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "leagueId", value: leagueIDs),
            URLQueryItem(name: "season", value: String(season))
        ]
        return try await get(components.url!)
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
    let era: String?
    let whip: String?
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
