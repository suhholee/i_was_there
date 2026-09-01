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
    @State private var activeLeague: League = .mlb
    @State private var mlbFavoriteID: Int = 0
    @State private var kboFavoriteID: Int = 0
    @State private var homeMinPA: String = ""
    @State private var homeMinBF: String = ""
    @State private var savedSnapshot = SettingsSnapshot()
    @State private var showUnsavedChangesAlert = false

    private var profile: UserProfile? { profiles.first }

    private var hasLocalUnsavedChanges: Bool {
        currentSnapshot != savedSnapshot
    }

    private var currentSnapshot: SettingsSnapshot {
        SettingsSnapshot(
            displayName: displayName,
            activeLeague: activeLeague,
            mlbFavoriteID: mlbFavoriteID,
            kboFavoriteID: kboFavoriteID,
            homeMinPlateAppearances: parsedLeaderFilter(homeMinPA),
            homeMinBattersFaced: parsedLeaderFilter(homeMinBF)
        )
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
                    TextField("Display name", text: $displayName)

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
                    Text("MLB and KBO diaries stay separate on this device. Each league keeps its own favorite team.")
                        .font(.footnote)
                        .foregroundStyle(DesignTokens.secondaryText)
                } header: {
                    settingsSectionHeader("Data")
                }

                Section {
                    LabeledContent("App", value: "#iWasThere")
                    LabeledContent("Active API", value: activeLeague.apiLabel)
                    LabeledContent("Prototype", value: "KBO mode")
                } header: {
                    settingsSectionHeader("About")
                }
            }
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
            .onChange(of: hasLocalUnsavedChanges) { _, changed in
                hasUnsavedChanges = changed
            }
            .onChange(of: saveTrigger) { _, shouldSave in
                guard shouldSave else { return }
                saveAll()
                dismissKeyboard()
                saveTrigger = false
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
        guard let profile = profiles.first else { return }
        profile.displayName = displayName
        profile.league = activeLeague
        profile.homeMinPlateAppearances = parsedLeaderFilter(homeMinPA)
        profile.homeMinBattersFaced = parsedLeaderFilter(homeMinBF)

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
        savedSnapshot = currentSnapshot
        try? modelContext.save()
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
        activeLeague = profile.league
        mlbFavoriteID = profile.favoriteTeamID ?? 0
        kboFavoriteID = profile.favoriteKBOTeamID ?? 0
        homeMinPA = leaderFilterDisplay(profile.homeMinPlateAppearances)
        homeMinBF = leaderFilterDisplay(profile.homeMinBattersFaced)
        savedSnapshot = currentSnapshot
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
    var activeLeague: League = .mlb
    var mlbFavoriteID: Int = 0
    var kboFavoriteID: Int = 0
    var homeMinPlateAppearances: Int = 0
    var homeMinBattersFaced: Int = 0
}

#Preview {
    SettingsView(
        hasUnsavedChanges: .constant(false),
        saveTrigger: .constant(false),
        onBack: {}
    )
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
