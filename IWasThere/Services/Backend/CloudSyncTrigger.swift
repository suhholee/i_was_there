import SwiftData

/// Fire-and-forget cloud sync after local SwiftData saves.
@MainActor
enum CloudSyncTrigger {
    static func profile(modelContext: ModelContext) {
        guard let userId = AuthSession.shared.userId else { return }
        CloudSyncService.shared.syncProfile(modelContext: modelContext, userId: userId)
    }

    static func game(_ game: AttendedGame, modelContext: ModelContext) {
        guard let userId = AuthSession.shared.userId else { return }
        CloudSyncService.shared.syncGame(game, modelContext: modelContext, userId: userId)
    }
}
