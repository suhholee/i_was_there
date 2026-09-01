import Foundation
import SwiftData

/// Clears on-device diary data when switching accounts or signing out.
enum LocalUserDataStore {
    private static let lastCloudUserIdKey = "lastCloudSyncUserId"

    static func lastSyncedUserId() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: lastCloudUserIdKey) else { return nil }
        return UUID(uuidString: raw)
    }

    static func markSyncedUserId(_ userId: UUID) {
        UserDefaults.standard.set(userId.uuidString, forKey: lastCloudUserIdKey)
    }

    static func clearSyncedUserId() {
        UserDefaults.standard.removeObject(forKey: lastCloudUserIdKey)
    }

    static func clearUserData(modelContext: ModelContext) {
        if let games = try? modelContext.fetch(FetchDescriptor<AttendedGame>()) {
            for game in games {
                for photo in game.photos {
                    PhotoStore.delete(relativePath: photo.relativePath)
                }
                modelContext.delete(game)
            }
        }

        if let profiles = try? modelContext.fetch(FetchDescriptor<UserProfile>()) {
            for profile in profiles {
                modelContext.delete(profile)
            }
        }

        try? modelContext.save()
    }
}
