import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Binding var hasUnsavedChanges: Bool
    @Binding var saveTrigger: Bool
    let onBack: () -> Void

    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var usernameStatus: SettingsUsernameStatus = .idle
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var avatarImage: UIImage?
    @State private var profileVisibility: ProfileVisibility = .public
    @State private var activeLeague: League = .mlb
    @State private var mlbFavoriteID: Int = 0
    @State private var kboFavoriteID: Int = 0
    @State private var homeMinPA: String = ""
    @State private var homeMinBF: String = ""
    @State private var homeBatterCategory: LeaderboardEngine.BatterCategory = .ops
    @State private var homePitcherCategory: LeaderboardEngine.PitcherCategory = .era
    @State private var savedSnapshot = SettingsSnapshot()
    @State private var savedAvatarImage: UIImage?
    @State private var showUnsavedChangesAlert = false
    @State private var showSignOutConfirmation = false

    private enum SettingsUsernameStatus: Equatable {
        case idle
        case checking
        case available
        case unavailable
        case invalid(String)
    }

    private var profile: UserProfile? { profiles.first }

    private var canSaveUsername: Bool {
        let normalized = UsernameRules.normalize(username)
        if normalized == profile?.username { return true }
        return usernameStatus == .available
    }

    private var hasLocalUnsavedChanges: Bool {
        currentSnapshot != savedSnapshot && canSaveUsername
    }

    private var currentSnapshot: SettingsSnapshot {
        SettingsSnapshot(
            displayName: displayName,
            username: UsernameRules.normalize(username),
            profileVisibility: profileVisibility,
            avatarChanged: avatarImage != savedAvatarImage,
            activeLeague: activeLeague,
            mlbFavoriteID: mlbFavoriteID,
            kboFavoriteID: kboFavoriteID,
            homeMinPlateAppearances: parsedLeaderFilter(homeMinPA),
            homeMinBattersFaced: parsedLeaderFilter(homeMinBF),
            homeBatterCategory: homeBatterCategory,
            homePitcherCategory: homePitcherCategory
        )
    }

    private var settingsBatterCategories: [LeaderboardEngine.BatterCategory] {
        LeaderboardEngine.batterCategories(for: activeLeague)
    }

    private var orderedMLBTeams: [MLBTeamInfo] {
        MLBTeamCatalog.orderedForPicker(
            favoring: mlbFavoriteID == 0 ? nil : mlbFavoriteID
        )
    }

    private var orderedKBOTeams: [KBOTeamInfo] {
        KBOTeamCatalog.orderedForPicker(
            favoring: kboFavoriteID == 0 ? nil : kboFavoriteID
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileAvatarPicker(
                        image: $avatarImage,
                        diameter: 88,
                        actionLabelBottomPadding: 8
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))

                    HStack(spacing: 8) {
                        Text("@")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.secondaryText)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(DesignTokens.surface.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    settingsSectionHeader("Account")
                } footer: {
                    settingsUsernameStatusFooter
                }

                Section {
                    Picker("Profile visibility", selection: $profileVisibility) {
                        ForEach(ProfileVisibility.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    TextField("Display name", text: $displayName)
                } header: {
                    settingsSectionHeader("Profile")
                } footer: {
                    Text(profileVisibility.subtitle)
                        .font(.footnote)
                }

                Section {
                    Picker("Mode", selection: $activeLeague) {
                        ForEach(League.allCases) { league in
                            Text(league.title).tag(league)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    settingsSectionHeader("League")
                }

                Section {
                    if activeLeague == .mlb {
                        Picker("Favorite team", selection: $mlbFavoriteID) {
                            Text("None").tag(0)
                            ForEach(orderedMLBTeams) { team in
                                Text(
                                    MLBTeamCatalog.pickerLabel(
                                        for: team,
                                        favoriteID: mlbFavoriteID == 0 ? nil : mlbFavoriteID
                                    )
                                )
                                .tag(team.id)
                            }
                        }
                    } else {
                        Picker("Favorite team", selection: $kboFavoriteID) {
                            Text("None").tag(0)
                            ForEach(orderedKBOTeams) { team in
                                Text(
                                    KBOTeamCatalog.pickerLabel(
                                        for: team,
                                        favoriteID: kboFavoriteID == 0 ? nil : kboFavoriteID
                                    )
                                )
                                .tag(team.id)
                            }
                        }
                    }
                } header: {
                    settingsSectionHeader("Profile")
                }

                Section {
                    TextField("Min plate appearances", text: $homeMinPA)
                        .keyboardType(.numberPad)

                    TextField("Min batters faced", text: $homeMinBF)
                        .keyboardType(.numberPad)
                } header: {
                    settingsSectionHeader("Leaders minimum playing time")
                } footer: {
                    Text("Applies to Your leaders on Home and the Leaders tab. Batters need at least this many plate appearances; pitchers need at least this many batters faced. Leave blank for no minimum.")
                        .font(.footnote)
                }

                Section {
                    Picker("Batter stat", selection: $homeBatterCategory) {
                        ForEach(settingsBatterCategories) { category in
                            Text(category.title).tag(category)
                        }
                    }

                    Picker("Pitcher stat", selection: $homePitcherCategory) {
                        ForEach(LeaderboardEngine.PitcherCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                } header: {
                    settingsSectionHeader("Leader stats")
                } footer: {
                    Text("Controls the main stat on Home leaders and the top player cards in each game.")
                        .font(.footnote)
                }

                Section {
                    LabeledContent("App", value: "#iWasThere")
                    LabeledContent("Active API", value: activeLeague.apiLabel)
                    LabeledContent("Prototype", value: "KBO mode")
                } header: {
                    settingsSectionHeader("About")
                }

                if AuthSession.shared.isAuthenticated {
                    Section {
                        NavigationLink {
                            RemoveAccountView()
                        } label: {
                            Text("Remove account")
                                .foregroundStyle(DesignTokens.loseRed)
                        }

                        Button {
                            showSignOutConfirmation = true
                        } label: {
                            Text("Sign out")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(DesignTokens.loseRed)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .tint(DesignTokens.primaryText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: attemptBack) {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveAll()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.primaryText)
                    .disabled(!hasLocalUnsavedChanges)
                }
            }
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                loadFromProfile()
                hasUnsavedChanges = hasLocalUnsavedChanges
            }
            .onChange(of: username) { _, newValue in
                scheduleUsernameCheck(for: newValue)
            }
            .onChange(of: hasLocalUnsavedChanges) { _, changed in
                hasUnsavedChanges = changed
            }
            .onChange(of: saveTrigger) { _, shouldSave in
                guard shouldSave else { return }
                saveAll()
                dismissKeyboard()
                saveTrigger = false
            }
            .onChange(of: activeLeague) { _, _ in
                normalizeBatterCategory()
            }
            .alert("Sign out?", isPresented: $showSignOutConfirmation) {
                Button("Sign out", role: .destructive) {
                    Task { await AuthSession.shared.signOut(modelContext: modelContext) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign in again to sync your diary.")
            }
            .alert("Save changes?", isPresented: $showUnsavedChangesAlert) {
                Button("Save") {
                    saveAll()
                    dismissKeyboard()
                    onBack()
                }
                .foregroundStyle(DesignTokens.primaryText)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Save before leaving Settings?")
            }
            .tint(DesignTokens.primaryText)
        }
    }

    @ViewBuilder
    private var settingsUsernameStatusFooter: some View {
        switch usernameStatus {
        case .idle:
            Text("Letters, numbers, and underscores only.")
                .font(.footnote)
        case .checking:
            Text("Checking availability…")
                .font(.footnote)
        case .available:
            Text("Username is available.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.winGreen)
        case .unavailable:
            Text("That username is taken.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.loseRed)
        case .invalid(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(DesignTokens.loseRed)
        }
    }

    private func scheduleUsernameCheck(for raw: String) {
        usernameCheckTask?.cancel()

        let normalized = UsernameRules.normalize(raw)
        if normalized == profile?.username {
            usernameStatus = .available
            return
        }

        if let message = UsernameRules.validationMessage(for: raw) {
            usernameStatus = .invalid(message)
            return
        }

        usernameStatus = .checking
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let available = await UsernameAvailabilityService.shared.isAvailable(normalized)
            guard !Task.isCancelled else { return }
            usernameStatus = available ? .available : .unavailable
        }
    }

    private func attemptBack() {
        dismissKeyboard()
        if hasLocalUnsavedChanges {
            showUnsavedChangesAlert = true
        } else {
            onBack()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func saveAll() {
        ensureProfile()
        guard let profile = profiles.first, canSaveUsername else { return }
        profile.setUsername(username)
        profile.visibility = profileVisibility
        profile.displayName = displayName
        try? ProfileAvatarPersistence.apply(image: avatarImage, to: profile)
        profile.league = activeLeague
        profile.homeMinPlateAppearances = parsedLeaderFilter(homeMinPA)
        profile.homeMinBattersFaced = parsedLeaderFilter(homeMinBF)
        profile.setHomeBatterCategory(homeBatterCategory)
        profile.setHomePitcherCategory(homePitcherCategory)

        if mlbFavoriteID == 0 {
            profile.setFavoriteTeam(id: nil, abbr: nil, for: .mlb)
        } else if let team = MLBTeamCatalog.team(id: mlbFavoriteID) {
            profile.setFavoriteTeam(id: team.id, abbr: team.abbreviation, for: .mlb)
        }

        if kboFavoriteID == 0 {
            profile.setFavoriteTeam(id: nil, abbr: nil, for: .kbo)
        } else if let team = KBOTeamCatalog.team(id: kboFavoriteID) {
            profile.setFavoriteTeam(id: team.id, abbr: team.abbreviation, for: .kbo)
        }

        homeMinPA = leaderFilterDisplay(profile.homeMinPlateAppearances)
        homeMinBF = leaderFilterDisplay(profile.homeMinBattersFaced)
        savedAvatarImage = avatarImage
        savedSnapshot = currentSnapshot
        usernameStatus = .available
        try? modelContext.save()
        CloudSyncTrigger.profile(modelContext: modelContext)
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(DesignTokens.secondaryText)
            .textCase(nil)
    }

    private func loadFromProfile() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        displayName = profile.displayName
        username = profile.username
        usernameStatus = profile.username.isEmpty ? .idle : .available
        avatarImage = ProfileAvatarPersistence.loadImage(for: profile)
        savedAvatarImage = avatarImage
        profileVisibility = profile.visibility
        activeLeague = profile.league
        mlbFavoriteID = profile.favoriteTeamID ?? 0
        kboFavoriteID = profile.favoriteKBOTeamID ?? 0
        homeMinPA = leaderFilterDisplay(profile.homeMinPlateAppearances)
        homeMinBF = leaderFilterDisplay(profile.homeMinBattersFaced)
        homeBatterCategory = profile.homeBatterCategory(for: activeLeague)
        homePitcherCategory = profile.homePitcherCategory()
        savedSnapshot = currentSnapshot
    }

    private func normalizeBatterCategory() {
        let allowed = settingsBatterCategories
        if !allowed.contains(homeBatterCategory), let first = allowed.first {
            homeBatterCategory = first
        }
    }

    private func leaderFilterDisplay(_ value: Int) -> String {
        value > 0 ? String(value) : ""
    }

    private func parsedLeaderFilter(_ text: String) -> Int {
        max(0, Int(text.filter(\.isNumber)) ?? 0)
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }
}

private struct SettingsSnapshot: Equatable {
    var displayName: String = ""
    var username: String = ""
    var profileVisibility: ProfileVisibility = .public
    var avatarChanged: Bool = false
    var activeLeague: League = .mlb
    var mlbFavoriteID: Int = 0
    var kboFavoriteID: Int = 0
    var homeMinPlateAppearances: Int = 0
    var homeMinBattersFaced: Int = 0
    var homeBatterCategory: LeaderboardEngine.BatterCategory = .ops
    var homePitcherCategory: LeaderboardEngine.PitcherCategory = .era
}

#Preview {
    SettingsView(
        hasUnsavedChanges: .constant(false),
        saveTrigger: .constant(false),
        onBack: {}
    )
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
