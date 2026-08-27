import SwiftUI
import SwiftData

struct RootTabView: View {
    @Query private var profiles: [UserProfile]
    @State private var selectedTab: AppTab = .home

    private var teamTheme: TeamTheme {
        TeamTheme.forTeamID(profiles.first?.favoriteTeamID)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GamesView()
                .tabItem { Label("Games", systemImage: "baseball") }
                .tag(AppTab.games)

            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            LeadersView()
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }
                .tag(AppTab.leaders)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .environment(\.teamTheme, teamTheme)
        .tint(teamTheme.accent)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.background.ignoresSafeArea())
    }
}

enum AppTab: Hashable {
    case games
    case home
    case leaders
    case settings
}

#Preview {
    RootTabView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
