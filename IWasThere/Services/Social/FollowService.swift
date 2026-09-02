import Foundation
import Supabase

@MainActor
final class FollowService {
    static let shared = FollowService()

    private init() {}

    func pendingRequestCount() async throws -> Int {
        let client = try requireClient()
        let count: Int = try await client
            .rpc("count_pending_follow_requests")
            .execute()
            .value
        return count
    }

    func incomingRequests() async throws -> [IncomingFollowRequest] {
        let client = try requireClient()
        return try await client
            .rpc("list_incoming_follow_requests")
            .execute()
            .value
    }

    func requestFollow(targetUserId: UUID) async throws -> FollowRelationshipStatus {
        let client = try requireClient()
        let status: String = try await client
            .rpc("request_follow", params: ["target_user_id": targetUserId.uuidString])
            .execute()
            .value
        return FollowRelationshipStatus(rawValue: status) ?? .outgoingPending
    }

    func acceptFollow(from requesterUserId: UUID) async throws {
        let client = try requireClient()
        try await client
            .rpc("accept_mutual_follow", params: ["requester_user_id": requesterUserId.uuidString])
            .execute()
    }

    func declineFollow(from requesterUserId: UUID) async throws {
        let client = try requireClient()
        try await client
            .rpc("decline_follow_request", params: ["requester_user_id": requesterUserId.uuidString])
            .execute()
    }

    func cancelFollowRequest(targetUserId: UUID) async throws {
        let client = try requireClient()
        try await client
            .rpc("cancel_follow_request", params: ["target_user_id": targetUserId.uuidString])
            .execute()
    }

    func unfollow(targetUserId: UUID) async throws {
        let client = try requireClient()
        try await client
            .rpc("unfollow_user", params: ["target_user_id": targetUserId.uuidString])
            .execute()
    }

    func listMutualFollows(limit: Int = 50) async throws -> [UserSearchResult] {
        let client = try requireClient()
        return try await client
            .rpc("list_mutual_follows", params: MutualFollowsParams(resultLimit: limit))
            .execute()
            .value
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseManager.client else {
            throw FollowServiceError.notConfigured
        }
        return client
    }

    enum FollowServiceError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase is not configured."
            }
        }
    }
}

private struct MutualFollowsParams: Encodable {
    let resultLimit: Int

    enum CodingKeys: String, CodingKey {
        case resultLimit = "result_limit"
    }
}
