import Foundation
import Supabase

@MainActor
final class UsernameAvailabilityService {
    static let shared = UsernameAvailabilityService()

    private init() {}

    func isAvailable(_ raw: String) async -> Bool {
        let normalized = UsernameRules.normalize(raw)
        guard UsernameRules.isValidFormat(normalized) else { return false }
        guard let client = SupabaseManager.client else { return false }

        do {
            let available: Bool = try await client
                .rpc("check_username_available", params: ["desired": normalized])
                .execute()
                .value
            return available
        } catch {
            return false
        }
    }
}
