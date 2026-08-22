import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var displayName: String = ""
    @State private var favoriteTeamID: Int = 0

    private var orderedTeams: [MLBTeamInfo] {
        MLBTeamCatalog.orderedForPicker(
            favoring: favoriteTeamID == 0 ? nil : favoriteTeamID
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display name", text: $displayName)
                        .onSubmit(saveProfile)

                    Picker("Favorite team", selection: $favoriteTeamID) {
                        Text("None").tag(0)
                        ForEach(orderedTeams) { team in
                            Text(
                                MLBTeamCatalog.pickerLabel(
                                    for: team,
                                    favoriteID: favoriteTeamID == 0 ? nil : favoriteTeamID
                                )
                            )
                            .tag(team.id)
                        }
                    }
                    .onChange(of: favoriteTeamID) { _, _ in
                        saveProfile()
                    }

                    Text("Games where your favorite team won show a green WIN badge.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Data") {
                    Text("Games and photos stay on this device (SwiftData). No cloud account in the prototype.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "#iWasThere")
                    LabeledContent("API", value: "MLB Stats API")
                    LabeledContent("Prototype", value: "Phase 1")
                }
            }
            .navigationTitle("Settings")
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                ensureProfile()
                displayName = profiles.first?.displayName ?? ""
                favoriteTeamID = profiles.first?.favoriteTeamID ?? 0
            }
            .onDisappear(perform: saveProfile)
        }
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }

    private func saveProfile() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        profile.displayName = displayName
        if favoriteTeamID == 0 {
            profile.favoriteTeamID = nil
            profile.favoriteTeamAbbr = nil
        } else if let team = MLBTeamCatalog.team(id: favoriteTeamID) {
            profile.favoriteTeamID = team.id
            profile.favoriteTeamAbbr = team.abbreviation
        }
        try? modelContext.save()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
