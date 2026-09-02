import Foundation
import Supabase
import SwiftData

@MainActor
final class GameInviteService {
    static let shared = GameInviteService()

    private init() {}

    func pendingInviteCount() async throws -> Int {
        let client = try requireClient()
        let count: Int = try await client
            .rpc("count_pending_game_invites")
            .execute()
            .value
        return count
    }

    func incomingInvites() async throws -> [IncomingGameInvite] {
        let client = try requireClient()
        return try await client
            .rpc("list_incoming_game_invites")
            .execute()
            .value
    }

    func sendInvitesForNewLinkedFriends(
        on game: AttendedGame,
        previousLinkedUserIds: Set<UUID>,
        modelContext: ModelContext
    ) async throws {
        guard let userId = AuthSession.shared.userId else {
            throw GameInviteError.notAuthenticated
        }

        let added = Set(game.friends.compactMap(\.resolvedLinkedUserId))
            .subtracting(previousLinkedUserIds)
        guard !added.isEmpty else { return }

        try await CloudSyncService.shared.syncGameAndWait(game, modelContext: modelContext, userId: userId)

        guard let sourceGameId = try await CloudSyncService.shared.cloudGameID(
            for: game,
            userId: userId
        ) else {
            throw GameInviteError.gameNotSynced
        }

        let client = try requireClient()
        for toUserId in added {
            let _: UUID = try await client
                .rpc(
                    "create_game_invite",
                    params: CreateGameInviteParams(
                        sourceGameId: sourceGameId,
                        toUserId: toUserId
                    )
                )
                .execute()
                .value
        }
    }

    func createInvite(
        for game: AttendedGame,
        toUserId: UUID,
        modelContext: ModelContext
    ) async throws {
        guard let userId = AuthSession.shared.userId else {
            throw GameInviteError.notAuthenticated
        }

        try await CloudSyncService.shared.syncGameAndWait(game, modelContext: modelContext, userId: userId)

        guard let sourceGameId = try await CloudSyncService.shared.cloudGameID(
            for: game,
            userId: userId
        ) else {
            throw GameInviteError.gameNotSynced
        }

        let client = try requireClient()
        let _: UUID = try await client
            .rpc(
                "create_game_invite",
                params: CreateGameInviteParams(
                    sourceGameId: sourceGameId,
                    toUserId: toUserId
                )
            )
            .execute()
            .value
    }

    func acceptInvite(_ inviteId: UUID, modelContext: ModelContext) async throws {
        guard let userId = AuthSession.shared.userId else {
            throw GameInviteError.notAuthenticated
        }

        let invite = try await incomingInvites().first(where: { $0.inviteId == inviteId })

        let client = try requireClient()
        let _: UUID = try await client
            .rpc("accept_game_invite", params: ["p_invite_id": inviteId.uuidString])
            .execute()
            .value

        await CloudSyncService.shared.pull(modelContext: modelContext, userId: userId)

        if let invite {
            let games = (try? modelContext.fetch(FetchDescriptor<AttendedGame>())) ?? []
            if let game = games.first(where: { $0.gameKey == invite.gameKey }),
               game.invitedFromUserId.isEmpty {
                game.invitedFromUserId = invite.fromUserId.uuidString
                try? modelContext.save()
            }
            if let game = games.first(where: { $0.gameKey == invite.gameKey }) {
                if await GameFriendStore.normalizeSharedCopyFriendsIfNeeded(
                    on: game,
                    modelContext: modelContext
                ) {
                    try? modelContext.save()
                    CloudSyncTrigger.game(game, modelContext: modelContext)
                }
            }
        }
    }

    func declineInvite(_ inviteId: UUID) async throws {
        let client = try requireClient()
        try await client
            .rpc("decline_game_invite", params: ["p_invite_id": inviteId.uuidString])
            .execute()
    }

    func unreadGameLeftCount() async throws -> Int {
        let client = try requireClient()
        let count: Int = try await client
            .rpc("count_unread_game_left_notifications")
            .execute()
            .value
        return count
    }

    func gameLeftNotifications() async throws -> [GameLeftNotification] {
        let client = try requireClient()
        return try await client
            .rpc("list_game_left_notifications")
            .execute()
            .value
    }

    func markGameLeftNotificationsRead() async throws {
        let client = try requireClient()
        try await client
            .rpc("mark_game_left_notifications_read")
            .execute()
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseManager.client else {
            throw GameInviteError.notConfigured
        }
        return client
    }

    enum GameInviteError: LocalizedError {
        case notConfigured
        case notAuthenticated
        case gameNotSynced

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase is not configured."
            case .notAuthenticated: "Sign in to send game invites."
            case .gameNotSynced: "Sync this game before inviting a friend."
            }
        }
    }
}

private struct CreateGameInviteParams: Encodable {
    let sourceGameId: UUID
    let toUserId: UUID

    enum CodingKeys: String, CodingKey {
        case sourceGameId = "source_game_id"
        case toUserId = "to_user_id"
    }
}
