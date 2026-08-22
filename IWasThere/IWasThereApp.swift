import SwiftUI
import SwiftData

@main
struct IWasThereApp: App {
    init() {
        AppAppearance.configureNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: [
            UserProfile.self,
            AttendedGame.self,
            GamePlayerStat.self,
            GamePhoto.self
        ])
    }
}
