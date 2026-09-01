import Foundation

/// Sports2i KBO JSON client (`sportsstatsjson.sports2i.com`). Unofficial; see Scripts/kbo_spike/SPIKE.md.
actor KBOClient {
    static let shared = KBOClient()

    private let session: URLSession
    private let baseURL = URL(string: "https://sportsstatsjson.sports2i.com/ws/BaseBall.asmx/")!
    private let userAgent = "IWasThere/0.1 (kbo; local-first)"

    /// In-memory player directory for the current season fetch (names / jersey).
    private var playerCache: [String: [Int: KBOPlayer]] = [:]
    private var stadiumCache: [String: [String: String]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func schedule(date: Date) async throws -> [KBOScheduleGame] {
        let season = Calendar.current.component(.year, from: date)
        let gDt = Self.gDt(from: date)
        let rows: [KBOScheduleGameDTO] = try await get("Game?season=\(season)&gDt=\(gDt)")
        var seen = Set<String>()
        return rows
            .filter { Self.isFirstTeamKBOGame($0) }
            .compactMap { dto -> KBOScheduleGame? in
                guard let id = dto.g_id, !id.isEmpty else { return nil }
                guard seen.insert(id).inserted else { return nil }
                return KBOScheduleGame(dto: dto)
            }
            .sorted { $0.gameID < $1.gameID }
    }

    /// KBO first-team games (`le_id=1`, `sp_id=1`) including postseason (`sr_id` ≠ `0`).
    private static func isFirstTeamKBOGame(_ dto: KBOScheduleGameDTO) -> Bool {
        let leagueOK = dto.le_id == "1" || dto.le_id == nil
        let sportOK = dto.sp_id == "1" || dto.sp_id == nil
        return leagueOK && sportOK
    }

    func stadiums(season: Int) async throws -> [String: String] {
        let key = String(season)
        if let cached = stadiumCache[key] { return cached }
        let rows: [KBOStadiumDTO] = try await get("Stadium?season=\(season)")
        var map: [String: String] = [:]
        for row in rows where row.le_id == "1" || row.le_id == nil {
            guard let code = row.s_id, let name = row.s_nm,
                  !code.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            map[code] = KBOStadiumCatalog.canonicalName(
                stadiumCode: code,
                apiName: name,
                homeTeamCode: "",
                homeTeamID: 0
            )
        }
        stadiumCache[key] = map
        return map
    }

    func boxPayload(game: KBOScheduleGame) async throws -> KBOBoxPayload {
        let season = game.season
        let gDt = game.gDt
        async let teamRec: [KBOTeamRecordDTO] = get("GameTeamRecord?season=\(season)&gDt=\(gDt)")
        async let starters: [KBOStarterDTO] = get("GameStartPitcherRecord?season=\(season)&gDt=\(gDt)")
        async let hitters: [KBOHitterBoxDTO] = get("GameHitterBoxScore?season=\(season)&gDt=\(gDt)")
        async let pitchers: [KBOPitcherBoxDTO] = get("GamePitcherBoxScore?season=\(season)&gDt=\(gDt)")
        let players = try await players(season: season)
        let stadiumMap = try await stadiums(season: season)
        let apiVenue = stadiumMap[game.stadiumCode] ?? ""

        let gid = game.gameID
        return KBOBoxPayload(
            game: game,
            teamRecords: try await teamRec.filter { $0.g_id == gid },
            starters: try await starters.first { $0.g_id == gid },
            hitters: try await hitters.filter { $0.g_id == gid },
            pitchers: try await pitchers.filter { $0.g_id == gid },
            players: players,
            venueName: KBOTeamCatalog.resolvedVenueName(
                apiName: apiVenue,
                stadiumCode: game.stadiumCode,
                homeTeamCode: game.homeCode,
                homeTeamID: game.homeTeam.id
            )
        )
    }

    func standings(season: Int) async throws -> [KBOStandingRow] {
        let gDt = "\(season)1001"
        let rows: [KBOTeamRankDTO] = try await get("TeamRank?season=\(season)&gDt=\(gDt)")
        return rows
            .filter { $0.le_id == "1" && ($0.sr_id == "0" || $0.sr_id == nil) && ($0.group_sc ?? "").isEmpty }
            .compactMap { dto in
                guard let code = dto.t_id, let team = KBOTeamCatalog.team(code: code) else { return nil }
                return KBOStandingRow(
                    teamID: team.id,
                    teamCode: code,
                    wins: Int(dto.w_cn ?? "") ?? 0,
                    losses: Int(dto.l_cn ?? "") ?? 0,
                    draws: Int(dto.d_cn ?? "") ?? 0,
                    winningPercentage: dto.wra_rt
                )
            }
            .sorted { $0.wins == $1.wins ? $0.losses < $1.losses : $0.wins > $1.wins }
    }

    func players(season: Int) async throws -> [Int: KBOPlayer] {
        let key = String(season)
        if let cached = playerCache[key] { return cached }
        let rows: [KBOPlayerDTO] = try await get("Player?season=\(season)")
        var map: [Int: KBOPlayer] = [:]
        for row in rows where row.le_id == "1" {
            guard let id = Int(row.p_id ?? "") else { continue }
            let name = row.p_full_nm?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? row.p_nm?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Player \(id)"
            map[id] = KBOPlayer(
                id: id,
                name: name,
                jerseyNumber: row.back_no ?? "",
                teamCode: row.t_id ?? "",
                position: row.pos_va ?? ""
            )
        }
        playerCache[key] = map
        return map
    }

    private func get<T: Decodable>(_ pathAndQuery: String) async throws -> T {
        guard let url = URL(string: pathAndQuery, relativeTo: baseURL)?.absoluteURL else {
            throw KBOClientError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw KBOClientError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KBOClientError.decode(error)
        }
    }

    static func gDt(from date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d%02d%02d", y, m, d)
    }
}

enum KBOClientError: LocalizedError {
    case badURL
    case badStatus(Int)
    case decode(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid KBO API URL."
        case .badStatus(let code): return "KBO API error (\(code))."
        case .decode: return "Could not read KBO API response."
        }
    }
}

// MARK: - Domain

struct KBOScheduleGame: Identifiable, Hashable, Sendable {
    var id: String { gameID }
    let gameID: String
    let season: Int
    let gDt: String
    let homeCode: String
    let awayCode: String
    let stateCode: String
    let gameDateText: String
    /// Sports2i series id (`0` = regular season).
    let seriesID: String
    /// Sports2i stadium code (`s_id`).
    let stadiumCode: String

    var isFinal: Bool { stateCode == "3" }
    var isRegularSeason: Bool { seriesID == "0" || seriesID.isEmpty }

    var homeTeam: KBOTeamInfo { KBOTeamCatalog.team(code: homeCode) ?? .init(id: 9199, code: homeCode, name: homeCode, abbreviation: homeCode, homeStadiumName: "") }
    var awayTeam: KBOTeamInfo { KBOTeamCatalog.team(code: awayCode) ?? .init(id: 9198, code: awayCode, name: awayCode, abbreviation: awayCode, homeStadiumName: "") }

    var matchupLabel: String {
        let base = "\(awayTeam.name) @ \(homeTeam.name)"
        if let gameNumber = gameNumberLabel {
            return "\(base) · \(gameNumber)"
        }
        return base
    }

    /// Doubleheader game index from `g_id` suffix (e.g. `…HHLG1` → Game 2).
    var gameNumberLabel: String? {
        guard gameID.count >= 2 else { return nil }
        let suffix = gameID.suffix(2)
        guard suffix.last == "0", let digit = suffix.first, digit.isNumber else { return nil }
        let number = Int(String(digit)) ?? 0
        return "Game \(number + 1)"
    }

    init(dto: KBOScheduleGameDTO) {
        gameID = dto.g_id ?? ""
        season = Int(dto.season_id ?? "") ?? Calendar.current.component(.year, from: Date())
        homeCode = dto.h_t_id ?? ""
        awayCode = dto.a_t_id ?? ""
        stateCode = dto.state_sc ?? ""
        gameDateText = dto.g_dt ?? ""
        seriesID = dto.sr_id ?? "0"
        stadiumCode = dto.s_id ?? ""
        if let raw = dto.g_id, raw.count >= 8 {
            gDt = String(raw.prefix(8))
        } else {
            gDt = ""
        }
    }
}

struct KBOBoxPayload: Sendable {
    let game: KBOScheduleGame
    let teamRecords: [KBOTeamRecordDTO]
    let starters: KBOStarterDTO?
    let hitters: [KBOHitterBoxDTO]
    let pitchers: [KBOPitcherBoxDTO]
    let players: [Int: KBOPlayer]
    let venueName: String
}

struct KBOPlayer: Sendable {
    let id: Int
    let name: String
    let jerseyNumber: String
    let teamCode: String
    let position: String
}

struct KBOStandingRow: Sendable {
    let teamID: Int
    let teamCode: String
    let wins: Int
    let losses: Int
    let draws: Int
    let winningPercentage: String?
}

// MARK: - DTOs (Sports2i stringly-typed JSON)

struct KBOScheduleGameDTO: Decodable, Sendable {
    let sp_id: String?
    let le_id: String?
    let sr_id: String?
    let season_id: String?
    let g_id: String?
    let h_t_id: String?
    let a_t_id: String?
    let s_id: String?
    let g_dt: String?
    let state_sc: String?
}

struct KBOStadiumDTO: Decodable, Sendable {
    let le_id: String?
    let s_id: String?
    let s_nm: String?
}

struct KBOTeamRecordDTO: Decodable, Sendable {
    let g_id: String?
    let t_id: String?
    let result_sc: String?
}

struct KBOStarterDTO: Decodable, Sendable {
    let g_id: String?
    let t_pit_p_id: String?
    let b_pit_p_id: String?
}

struct KBOHitterBoxDTO: Decodable, Sendable {
    let g_id: String?
    let p_id: String?
    let tb_sc: String?
    let bat_order_no: String?
    let pos_if: String?
    let ab_cn: String?
    let run_cn: String?
    let hit_cn: String?
    let rbi_cn: String?
}

struct KBOPitcherBoxDTO: Decodable, Sendable {
    let g_id: String?
    let p_id: String?
    let tb_sc: String?
    let turn_no: String?
    let result_sc: String?
    let inn2_cn: String?
    let hit_cn: String?
    let hr_cn: String?
    let bbhp_cn: String?
    let kk_cn: String?
    let r_cn: String?
    let er_cn: String?
}

struct KBOTeamRankDTO: Decodable, Sendable {
    let le_id: String?
    let sr_id: String?
    let t_id: String?
    let group_sc: String?
    let rank_no: String?
    let w_cn: String?
    let l_cn: String?
    let d_cn: String?
    let wra_rt: String?
}

struct KBOPlayerDTO: Decodable, Sendable {
    let le_id: String?
    let p_id: String?
    let t_id: String?
    let p_nm: String?
    let p_full_nm: String?
    let back_no: String?
    let pos_va: String?
}
