import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var allGames: [AttendedGame]
    @State private var selectedTab: AppTab = .home
    @State private var tabBeforeSettings: AppTab = .home
    @State private var pendingGamesFriendFilter: GameFriendFilterOption?
    @State private var settingsHasUnsavedChanges = false
    @State private var settingsSaveTrigger = false
    @State private var showSettingsLeaveAlert = false
    @State private var pendingTabAfterSettings: AppTab?

    private var profile: UserProfile? { profiles.first }
    private var activeLeague: League { profile?.league ?? .mlb }

    private var teamTheme: TeamTheme {
        TeamTheme.forTeamID(profile?.favoriteTeamID(for: activeLeague))
    }

    var body: some View {
        TabView(selection: tabSelection) {
            HomeView(selectedTab: $selectedTab)
                .id(activeLeague)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            GamesView(externalFriendFilter: $pendingGamesFriendFilter)
                .id(activeLeague)
                .tabItem { Label("Games", systemImage: "baseball") }
                .tag(AppTab.games)

            LeadersView()
                .id(activeLeague)
                .tabItem { Label("Leaders", systemImage: "trophy.fill") }
                .tag(AppTab.leaders)

            PeopleView()
                .tabItem { Label("People", systemImage: "person.2.fill") }
                .tag(AppTab.people)

            SettingsView(
                hasUnsavedChanges: $settingsHasUnsavedChanges,
                saveTrigger: $settingsSaveTrigger,
                onBack: { leaveSettings(to: tabBeforeSettings) }
            )
            .id(activeLeague)
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppTab.settings)
        }
        .environment(\.teamTheme, teamTheme)
        .environment(\.openGamesTogether, { friend in openGamesTogether(with: friend) })
        .tint(DesignTokens.primaryText)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.background.ignoresSafeArea())
        .alert("Save changes?", isPresented: $showSettingsLeaveAlert) {
            Button("Save") {
                settingsSaveTrigger = true
                if let pendingTabAfterSettings {
                    selectedTab = pendingTabAfterSettings
                    self.pendingTabAfterSettings = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingTabAfterSettings = nil
            }
        } message: {
            Text("You have unsaved changes. Save before leaving Settings?")
        }
        .tint(DesignTokens.primaryText)
        .task(id: allGames.count) {
            backfillLeagueKeysIfNeeded()
            // Yield so the tab UI can appear before one-time friend migration runs.
            try? await Task.sleep(for: .milliseconds(200))
            GameFriendStore.backfillFromLegacyCompanions(games: allGames, modelContext: modelContext)
        }
        .onChange(of: activeLeague) { _, _ in
            selectedTab = .home
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if selectedTab == .settings && newTab != .settings && settingsHasUnsavedChanges {
                    pendingTabAfterSettings = newTab
                    showSettingsLeaveAlert = true
                    return
                }
                if newTab == .settings && selectedTab != .settings {
                    tabBeforeSettings = selectedTab
                }
                selectedTab = newTab
            }
        )
    }

    private func leaveSettings(to tab: AppTab) {
        if settingsHasUnsavedChanges {
            pendingTabAfterSettings = tab
            showSettingsLeaveAlert = true
        } else {
            selectedTab = tab
        }
    }

    private func backfillLeagueKeysIfNeeded() {
        var changed = false
        for game in allGames where game.gameKey.isEmpty || game.league.isEmpty {
            game.ensureGameKey()
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }

    private func openGamesTogether(with friend: UserSearchResult) {
        pendingGamesFriendFilter = GameFriendFilterOption(friend: friend)
        selectedTab = .games
    }
}

private struct OpenGamesTogetherKey: EnvironmentKey {
    static let defaultValue: ((UserSearchResult) -> Void)? = nil
}

extension EnvironmentValues {
    var openGamesTogether: ((UserSearchResult) -> Void)? {
        get { self[OpenGamesTogetherKey.self] }
        set { self[OpenGamesTogetherKey.self] = newValue }
    }
}

enum AppTab: Hashable {
    case games
    case home
    case leaders
    case people
    case settings
}

#Preview {
    RootTabView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
