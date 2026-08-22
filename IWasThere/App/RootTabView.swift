import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case games
    case home
    case leaders
    case settings
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            GamesView()
                .tabItem { Label("Games", systemImage: "baseball") }
                .tag(AppTab.games)

            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            LeadersView()
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }
                .tag(AppTab.leaders)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(DesignTokens.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
