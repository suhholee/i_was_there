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

    func loadVisibleGames(
        for profile: PublicUserProfile,
        modelContext: ModelContext
    ) async throws -> [AttendedGame] {
        guard profile.canViewGames else { return [] }

        let client = try requireClient()
        let rows: [CloudAttendedGameRow] = try await client
            .rpc("list_user_attended_games", params: ["target_user_id": profile.userId.uuidString])
            .execute()
            .value

        var hydrated: [AttendedGame] = []
        var keys = Set<String>()

        for row in rows {
            let friends: [RemoteGameFriendRow] = try await client
                .rpc("list_user_game_friends", params: ["p_game_id": row.id.uuidString])
                .execute()
                .value

            let game = try await GameHydrationService.hydrate(
                row: row,
                friends: friends.map {
                    DiaryFriendEntry(name: $0.name, linkedUserId: nil)
                },
                modelContext: modelContext,
                existingGameKeys: keys
            )
            keys.insert(row.gameKey)

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

            hydrated.append(game)
        }

        try? modelContext.save()
        return hydrated
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
