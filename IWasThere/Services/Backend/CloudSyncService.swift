import Foundation
import Supabase
import SwiftData
import UIKit

/// Syncs user-owned rows to Supabase. Game/player stats stay on-device via API hydration.
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private(set) var isSyncing = false
    private(set) var lastSyncError: String?
    private let photoBucket = "game-photos"

    private init() {}

    func performFullSync(modelContext: ModelContext, userId: UUID) async {
        guard let client = SupabaseManager.client else { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            let priorUserId = LocalUserDataStore.lastSyncedUserId()
            if priorUserId != userId {
                LocalUserDataStore.clearUserData(modelContext: modelContext)
                try await pullAndHydrate(client: client, modelContext: modelContext, userId: userId)
            } else {
                try await pushProfile(client: client, modelContext: modelContext, userId: userId)
                try await pushAllGames(client: client, modelContext: modelContext, userId: userId)
                try await pullAndHydrate(client: client, modelContext: modelContext, userId: userId)
            }
            LocalUserDataStore.markSyncedUserId(userId)
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func syncProfile(modelContext: ModelContext, userId: UUID) {
        Task {
            guard let client = SupabaseManager.client else { return }
            try? await pushProfile(client: client, modelContext: modelContext, userId: userId)
        }
    }

    func syncGame(_ game: AttendedGame, modelContext: ModelContext, userId: UUID) {
        Task {
            guard let client = SupabaseManager.client else { return }
            try? await pushGame(client: client, game: game, userId: userId, modelContext: modelContext)
        }
    }

    // MARK: - Push

    private func pushProfile(
        client: SupabaseClient,
        modelContext: ModelContext,
        userId: UUID
    ) async throws {
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try modelContext.fetch(descriptor).first else { return }
        let row = CloudProfileUpsert.from(profile: profile, userId: userId)
        try await client
            .from("profiles")
            .upsert(row, onConflict: "user_id")
            .execute()
    }

    private func pushAllGames(
        client: SupabaseClient,
        modelContext: ModelContext,
        userId: UUID
    ) async throws {
        let games = try modelContext.fetch(FetchDescriptor<AttendedGame>())
        for game in games {
            try await pushGame(client: client, game: game, userId: userId, modelContext: modelContext)
        }
    }

    private func pushGame(
        client: SupabaseClient,
        game: AttendedGame,
        userId: UUID,
        modelContext: ModelContext
    ) async throws {
        game.ensureGameKey()
        let upsert = CloudAttendedGameUpsert.from(game: game, userId: userId)
        try await client
            .from("attended_games")
            .upsert(upsert, onConflict: "user_id,game_key")
            .execute()

        guard let cloudRow = try await fetchCloudGame(
            client: client,
            userId: userId,
            gameKey: game.gameKey
        ) else { return }

        try await client
            .from("game_friends")
            .delete()
            .eq("game_id", value: cloudRow.id.uuidString)
            .execute()

        let friendRows = game.friendNames.map {
            CloudGameFriendInsert(userId: userId, gameId: cloudRow.id, name: $0)
        }
        if !friendRows.isEmpty {
            try await client.from("game_friends").insert(friendRows).execute()
        }

        for photo in game.photos where photo.cloudStoragePath.isEmpty {
            try await uploadPhoto(
                client: client,
                photo: photo,
                game: game,
                cloudGameId: cloudRow.id,
                userId: userId,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Pull + hydrate

    private func pullAndHydrate(
        client: SupabaseClient,
        modelContext: ModelContext,
        userId: UUID
    ) async throws {
        let cloudProfile: CloudProfileRow? = try await client
            .from("profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value
        if let cloudProfile {
            let descriptor = FetchDescriptor<UserProfile>()
            if let local = try modelContext.fetch(descriptor).first {
                cloudProfile.apply(to: local)
            } else {
                let profile = UserProfile()
                cloudProfile.apply(to: profile)
                modelContext.insert(profile)
            }
        }

        let cloudGames: [CloudAttendedGameRow] = try await client
            .from("attended_games")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("game_date", ascending: false)
            .execute()
            .value

        let localGames = try modelContext.fetch(FetchDescriptor<AttendedGame>())
        var localKeys = Set(localGames.map(\.gameKey))

        for row in cloudGames {
            if localKeys.contains(row.gameKey) {
                if let local = localGames.first(where: { $0.gameKey == row.gameKey }) {
                    local.eventTitle = row.eventTitle
                    local.note = row.note
                }
                continue
            }

            let friends: [CloudGameFriendRow] = try await client
                .from("game_friends")
                .select()
                .eq("game_id", value: row.id.uuidString)
                .execute()
                .value

            let hydrated = try await GameHydrationService.hydrate(
                row: row,
                friendNames: friends.map(\.name),
                modelContext: modelContext,
                existingGameKeys: localKeys
            )
            localKeys.insert(row.gameKey)

            let photos: [CloudGamePhotoRow] = try await client
                .from("game_photos")
                .select()
                .eq("game_id", value: row.id.uuidString)
                .execute()
                .value

            for cloudPhoto in photos {
                try await downloadPhoto(
                    client: client,
                    cloudPhoto: cloudPhoto,
                    game: hydrated,
                    modelContext: modelContext
                )
            }
        }

        try? modelContext.save()
    }

    // MARK: - Photos

    private func uploadPhoto(
        client: SupabaseClient,
        photo: GamePhoto,
        game: AttendedGame,
        cloudGameId: UUID,
        userId: UUID,
        modelContext: ModelContext
    ) async throws {
        let localURL = PhotoStore.absoluteURL(relativePath: photo.relativePath)
        guard let data = try? Data(contentsOf: localURL) else { return }

        let path = "\(userId.uuidString)/\(game.gameKey)/\(UUID().uuidString).jpg"
        try await client.storage
            .from(photoBucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        photo.cloudStoragePath = path
        let row = CloudGamePhotoInsert(userId: userId, gameId: cloudGameId, storagePath: path)
        try await client.from("game_photos").insert(row).execute()
        try? modelContext.save()
    }

    private func downloadPhoto(
        client: SupabaseClient,
        cloudPhoto: CloudGamePhotoRow,
        game: AttendedGame,
        modelContext: ModelContext
    ) async throws {
        if game.photos.contains(where: { $0.cloudStoragePath == cloudPhoto.storagePath }) {
            return
        }
        let data = try await client.storage
            .from(photoBucket)
            .download(path: cloudPhoto.storagePath)

        guard let image = UIImage(data: data),
              let jpeg = PhotoStore.jpegData(from: image)
        else { return }

        let relative = try PhotoStore.saveJPEG(jpeg, gamePk: game.mlbGamePk)
        let photo = GamePhoto(relativePath: relative, cloudStoragePath: cloudPhoto.storagePath)
        photo.game = game
        modelContext.insert(photo)
        game.photos.append(photo)
    }

    private func fetchCloudGame(
        client: SupabaseClient,
        userId: UUID,
        gameKey: String
    ) async throws -> CloudAttendedGameRow? {
        let rows: [CloudAttendedGameRow] = try await client
            .from("attended_games")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("game_key", value: gameKey)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
}
