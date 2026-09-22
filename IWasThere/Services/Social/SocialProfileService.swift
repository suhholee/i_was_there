import Foundation
import Supabase
import SwiftData
import UIKit

@MainActor
final class SocialProfileService {
    static let shared = SocialProfileService()

    private let avatarBucket = "avatars"
    private let photoBucket = "game-photos"
    private var avatarCache: [String: UIImage] = [:]

    private init() {}

    func searchUsers(query: String, limit: Int = 25) async throws -> [UserSearchResult] {
        let client = try requireClient()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let rows: [UserSearchResult] = try await client
            .rpc("search_users", params: SearchUsersParams(searchQuery: trimmed, resultLimit: limit))
            .execute()
            .value
        return rows.filter { $0.userId != AuthSession.shared.userId }
    }

    func fetchProfile(userId: UUID) async throws -> PublicUserProfile? {
        let client = try requireClient()
        let rows: [PublicUserProfile] = try await client
            .rpc("get_user_profile", params: ["target_user_id": userId.uuidString])
            .execute()
            .value
        return rows.first
    }

    func fetchProfile(username: String) async throws -> PublicUserProfile? {
        let client = try requireClient()
        let normalized = UsernameRules.normalize(username)
        guard !normalized.isEmpty else { return nil }

        let rows: [PublicUserProfile] = try await client
            .rpc("get_user_profile_by_username", params: ["target_username": normalized])
            .execute()
            .value
        return rows.first
    }

    /// Fast path for People → profile Games list.
    /// Returns cloud rows immediately (scores/starters when present). Friend names are attached separately.
    func loadVisibleGameSummaries(for profile: PublicUserProfile) async throws -> [RemoteGameSummary] {
        guard profile.canViewGames else { return [] }

        let client = try requireClient()
        let rows: [CloudAttendedGameRow] = try await client
            .rpc("list_user_attended_games", params: ["target_user_id": profile.userId.uuidString])
            .execute()
            .value

        return rows.map { row in
            RemoteGameSummary(
                id: row.id,
                row: row,
                friendNames: []
            )
        }
    }

    /// Fills `friendNames` without blocking the initial games + score paint.
    func attachFriendNames(
        to summaries: [RemoteGameSummary],
        profileUserId: UUID
    ) async -> [RemoteGameSummary] {
        guard !summaries.isEmpty else { return summaries }
        guard let client = try? requireClient() else { return summaries }

        let namesByGame = await loadFriendNamesByGame(
            client: client,
            userId: profileUserId,
            gameIds: summaries.map(\.id)
        )
        guard !namesByGame.isEmpty else { return summaries }

        return summaries.map { summary in
            RemoteGameSummary(
                id: summary.id,
                row: summary.row,
                friendNames: namesByGame[summary.id] ?? summary.friendNames
            )
        }
    }

    /// Lightweight schedule/box fill-in for cards still missing scores/team ids.
    /// Does not block the initial list; call after `loadVisibleGameSummaries`.
    func enrichMissingDisplaySnapshots(
        _ summaries: [RemoteGameSummary]
    ) async -> [RemoteGameSummary] {
        let missing = summaries.filter(\.needsEnrichment)
        guard !missing.isEmpty else { return summaries }

        var updates: [UUID: CloudAttendedGameRow] = [:]
        await withTaskGroup(of: (UUID, CloudAttendedGameRow)?.self) { group in
            for summary in missing {
                group.addTask { @MainActor in
                    guard let enriched = await Self.fetchDisplaySnapshot(for: summary.row) else {
                        return nil
                    }
                    return (summary.id, enriched)
                }
            }
            for await item in group {
                guard let item else { continue }
                updates[item.0] = item.1
            }
        }

        guard !updates.isEmpty else { return summaries }
        return summaries.map { summary in
            guard let row = updates[summary.id] else { return summary }
            return summary.applying(row: row)
        }
    }

    private static func fetchDisplaySnapshot(for row: CloudAttendedGameRow) async -> CloudAttendedGameRow? {
        let league = League(rawValue: row.league) ?? .mlb
        switch league {
        case .mlb:
            return await fetchMLBDisplaySnapshot(for: row)
        case .kbo:
            return await fetchKBODisplaySnapshot(for: row)
        }
    }

    private static func fetchMLBDisplaySnapshot(for row: CloudAttendedGameRow) async -> CloudAttendedGameRow? {
        do {
            let needsStarters = (row.homeStarterName ?? "").isEmpty || (row.awayStarterName ?? "").isEmpty

            async let scheduleTask = MLBClient.shared.findScheduleGame(
                gamePk: row.mlbGamePk,
                around: row.gameDate
            )
            async let boxscoreTask: MLBBoxscoreResponse? = {
                guard needsStarters else { return nil }
                return try? await MLBClient.shared.boxscore(gamePk: row.mlbGamePk)
            }()

            let schedule = try await scheduleTask
            let boxscore = await boxscoreTask

            let awayScore = schedule.teams.away.score ?? row.awayScore
            let homeScore = schedule.teams.home.score ?? row.homeScore
            let awayWon = schedule.teams.away.isWinner
                ?? (awayScore != nil && homeScore != nil ? awayScore! > homeScore! : row.awayWon)
            let homeWon = schedule.teams.home.isWinner
                ?? (awayScore != nil && homeScore != nil ? homeScore! > awayScore! : row.homeWon)

            var awayStarter = row.awayStarterName
            var homeStarter = row.homeStarterName
            if let boxscore {
                if (awayStarter ?? "").isEmpty {
                    awayStarter = StarterBackfill.starterName(from: boxscore.teams.away)
                }
                if (homeStarter ?? "").isEmpty {
                    homeStarter = StarterBackfill.starterName(from: boxscore.teams.home)
                }
            }

            return row.withDisplaySnapshot(
                homeScore: homeScore,
                awayScore: awayScore,
                homeTeamId: schedule.teams.home.team.id,
                awayTeamId: schedule.teams.away.team.id,
                homeStarterName: homeStarter,
                awayStarterName: awayStarter,
                homeWon: homeWon,
                awayWon: awayWon,
                awayTeamName: schedule.teams.away.team.name,
                homeTeamName: schedule.teams.home.team.name
            )
        } catch {
            return nil
        }
    }

    private static func fetchKBODisplaySnapshot(for row: CloudAttendedGameRow) async -> CloudAttendedGameRow? {
        guard !row.kboGameId.isEmpty else { return nil }
        do {
            let schedule = try await KBOClient.shared.findScheduleGame(
                gameID: row.kboGameId,
                gDt: row.kboGDt,
                season: row.season
            )
            let payload = try await KBOClient.shared.boxPayload(game: schedule)
            let attended = try KBOBoxscoreImporter.makeAttendedGame(
                from: payload,
                existingGameKeys: []
            )
            return row.withDisplaySnapshot(
                homeScore: attended.homeScore,
                awayScore: attended.awayScore,
                homeTeamId: attended.homeTeamID,
                awayTeamId: attended.awayTeamID,
                homeStarterName: attended.homeStarterName,
                awayStarterName: attended.awayStarterName,
                homeWon: attended.homeWon,
                awayWon: attended.awayWon,
                awayTeamName: attended.awayTeamName,
                homeTeamName: attended.homeTeamName
            )
        } catch {
            return nil
        }
    }

    /// Prefers the batched RPC; falls back to parallel per-game calls if migration 017 is not applied yet.
    private func loadFriendNamesByGame(
        client: SupabaseClient,
        userId: UUID,
        gameIds: [UUID]
    ) async -> [UUID: [String]] {
        guard !gameIds.isEmpty else { return [:] }

        do {
            let friendRows: [RemoteGameFriendNameRow] = try await client
                .rpc("list_user_games_friend_names", params: ["target_user_id": userId.uuidString])
                .execute()
                .value
            var namesByGame: [UUID: [String]] = [:]
            for friend in friendRows {
                namesByGame[friend.gameId, default: []].append(friend.name)
            }
            return namesByGame
        } catch {
            var namesByGame: [UUID: [String]] = [:]
            await withTaskGroup(of: (UUID, [String]).self) { group in
                for gameId in gameIds {
                    group.addTask { @MainActor in
                        let friends: [RemoteGameFriendRow] = (try? await client
                            .rpc("list_user_game_friends", params: ["p_game_id": gameId.uuidString])
                            .execute()
                            .value) ?? []
                        return (gameId, friends.map(\.name))
                    }
                }
                for await (gameId, names) in group {
                    namesByGame[gameId] = names
                }
            }
            return namesByGame
        }
    }

    /// Hydrates a single remote game for detail (MLB/KBO + friends + photos).
    func loadVisibleGameDetail(
        summary: RemoteGameSummary,
        modelContext: ModelContext
    ) async throws -> AttendedGame {
        let client = try requireClient()
        let row = summary.row

        let friends: [DiaryFriendEntry]
        if summary.friendNames.isEmpty {
            let remoteFriends: [RemoteGameFriendRow] = try await client
                .rpc("list_user_game_friends", params: ["p_game_id": row.id.uuidString])
                .execute()
                .value
            friends = remoteFriends.map { DiaryFriendEntry(name: $0.name, linkedUserId: nil) }
        } else {
            friends = summary.friendNames.map { DiaryFriendEntry(name: $0, linkedUserId: nil) }
        }

        let game = try await GameHydrationService.hydrate(
            row: row,
            friends: friends,
            modelContext: modelContext,
            existingGameKeys: []
        )

        let photoRows: [RemoteGamePhotoRow] = try await client
            .rpc("list_user_game_photos", params: ["p_game_id": row.id.uuidString])
            .execute()
            .value
        for photoRow in photoRows {
            try await attachRemotePhoto(
                storagePath: photoRow.storagePath,
                to: game,
                modelContext: modelContext
            )
        }

        try? modelContext.save()
        return game
    }

    func downloadAvatar(path: String?, forceRefresh: Bool = false) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if forceRefresh {
            avatarCache.removeValue(forKey: path)
        } else if let cached = avatarCache[path] {
            return cached
        }

        guard let client = SupabaseManager.client else { return nil }
        do {
            let data = try await client.storage.from(avatarBucket).download(path: path)
            guard let image = UIImage(data: data) else { return nil }
            avatarCache[path] = image
            return image
        } catch {
            return nil
        }
    }

    func invalidateAvatarCache(for path: String?) {
        guard let path, !path.isEmpty else { return }
        avatarCache.removeValue(forKey: path)
    }

    private func attachRemotePhoto(
        storagePath: String,
        to game: AttendedGame,
        modelContext: ModelContext
    ) async throws {
        if game.photos.contains(where: { $0.cloudStoragePath == storagePath }) {
            return
        }

        guard let client = SupabaseManager.client else { return }
        let data = try await client.storage.from(photoBucket).download(path: storagePath)
        guard let image = UIImage(data: data),
              let jpeg = PhotoStore.jpegData(from: image)
        else { return }

        let relative = try PhotoStore.saveJPEG(jpeg, gamePk: game.mlbGamePk)
        let photo = GamePhoto(relativePath: relative, cloudStoragePath: storagePath)
        photo.game = game
        modelContext.insert(photo)
        game.photos.append(photo)
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseManager.client else {
            throw SocialProfileError.notConfigured
        }
        return client
    }

    enum SocialProfileError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase is not configured."
            }
        }
    }
}

private struct SearchUsersParams: Encodable {
    let searchQuery: String
    let resultLimit: Int

    enum CodingKeys: String, CodingKey {
        case searchQuery = "search_query"
        case resultLimit = "result_limit"
    }
}

enum EphemeralModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            AttendedGame.self,
            GamePlayerStat.self,
            GamePhoto.self,
            GameFriend.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
