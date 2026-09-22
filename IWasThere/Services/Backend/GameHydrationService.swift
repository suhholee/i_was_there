import Foundation
import SwiftData

/// Rebuilds `AttendedGame` + player lines from MLB/KBO APIs using cloud lookup keys.
@MainActor
enum GameHydrationService {
    /// Network-fetched boxscore materials, safe to gather in parallel before SwiftData inserts.
    struct PreparedGame {
        let row: CloudAttendedGameRow
        let friends: [DiaryFriendEntry]
        let payload: Payload
    }

    enum Payload {
        case mlb(schedule: MLBScheduleGame, boxscore: MLBBoxscoreResponse)
        case kbo(KBOBoxPayload)
    }

    static func hydrate(
        row: CloudAttendedGameRow,
        friends: [DiaryFriendEntry],
        modelContext: ModelContext,
        existingGameKeys: Set<String>
    ) async throws -> AttendedGame {
        let prepared = try await prepare(row: row, friends: friends)
        return try materialize(
            prepared,
            modelContext: modelContext,
            existingGameKeys: existingGameKeys
        )
    }

    /// Fetch schedule/boxscore (+ friends already resolved) without touching SwiftData.
    static func prepare(
        row: CloudAttendedGameRow,
        friends: [DiaryFriendEntry]
    ) async throws -> PreparedGame {
        let league = League(rawValue: row.league) ?? .mlb
        let payload: Payload

        switch league {
        case .mlb:
            let schedule = try await MLBClient.shared.findScheduleGame(
                gamePk: row.mlbGamePk,
                around: row.gameDate
            )
            let boxscore = try await MLBClient.shared.boxscore(gamePk: row.mlbGamePk)
            payload = .mlb(schedule: schedule, boxscore: boxscore)
        case .kbo:
            guard !row.kboGameId.isEmpty else {
                throw HydrationError.missingKBOIdentifier
            }
            let schedule = try await KBOClient.shared.findScheduleGame(
                gameID: row.kboGameId,
                gDt: row.kboGDt,
                season: row.season
            )
            let box = try await KBOClient.shared.boxPayload(game: schedule)
            payload = .kbo(box)
        }

        return PreparedGame(row: row, friends: friends, payload: payload)
    }

    /// Insert a prepared game into SwiftData (call serially).
    static func materialize(
        _ prepared: PreparedGame,
        modelContext: ModelContext,
        existingGameKeys: Set<String>
    ) throws -> AttendedGame {
        let row = prepared.row
        guard !existingGameKeys.contains(row.gameKey) else {
            throw HydrationError.duplicate(row.gameKey)
        }

        let attended: AttendedGame
        switch prepared.payload {
        case .mlb(let schedule, let boxscore):
            attended = try BoxscoreImporter.makeAttendedGame(
                from: schedule,
                boxscore: boxscore,
                existingGamePks: []
            )
        case .kbo(let box):
            attended = try KBOBoxscoreImporter.makeAttendedGame(
                from: box,
                existingGameKeys: []
            )
        }

        attended.eventTitle = row.eventTitle
        attended.note = row.note
        attended.friendsVisibleToOthers = row.friendsVisibleToOthers ?? true
        attended.rootedForTeamID = row.rootedForTeamId
        attended.includeRootedTeamInWinRate = row.includeRootedTeamInWinRate ?? false
        if let invitedFrom = row.invitedFromUserId {
            attended.invitedFromUserId = invitedFrom.uuidString
        }
        GameFriendStore.setFriends(entries: prepared.friends, on: attended, modelContext: modelContext)

        modelContext.insert(attended)
        for stat in attended.playerStats {
            stat.game = attended
        }
        return attended
    }

    enum HydrationError: LocalizedError {
        case duplicate(String)
        case missingKBOIdentifier

        var errorDescription: String? {
            switch self {
            case .duplicate(let key): return "Game \(key) is already on this device."
            case .missingKBOIdentifier: return "KBO game id missing from cloud record."
            }
        }
    }
}
