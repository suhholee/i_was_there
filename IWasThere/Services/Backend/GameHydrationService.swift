import Foundation
import SwiftData

/// Rebuilds `AttendedGame` + player lines from MLB/KBO APIs using cloud lookup keys.
@MainActor
enum GameHydrationService {
    static func hydrate(
        row: CloudAttendedGameRow,
        friendNames: [String],
        modelContext: ModelContext,
        existingGameKeys: Set<String>
    ) async throws -> AttendedGame {
        guard !existingGameKeys.contains(row.gameKey) else {
            throw HydrationError.duplicate(row.gameKey)
        }

        let league = League(rawValue: row.league) ?? .mlb
        let attended: AttendedGame

        switch league {
        case .mlb:
            let schedule = try await MLBClient.shared.findScheduleGame(
                gamePk: row.mlbGamePk,
                around: row.gameDate
            )
            let boxscore = try await MLBClient.shared.boxscore(gamePk: row.mlbGamePk)
            attended = try BoxscoreImporter.makeAttendedGame(
                from: schedule,
                boxscore: boxscore,
                existingGamePks: []
            )
        case .kbo:
            guard !row.kboGameId.isEmpty else {
                throw HydrationError.missingKBOIdentifier
            }
            let schedule = try await KBOClient.shared.findScheduleGame(
                gameID: row.kboGameId,
                gDt: row.kboGDt,
                season: row.season
            )
            let payload = try await KBOClient.shared.boxPayload(game: schedule)
            attended = try KBOBoxscoreImporter.makeAttendedGame(
                from: payload,
                existingGameKeys: []
            )
        }

        attended.eventTitle = row.eventTitle
        attended.note = row.note
        GameFriendStore.setFriends(names: friendNames, on: attended, modelContext: modelContext)

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
