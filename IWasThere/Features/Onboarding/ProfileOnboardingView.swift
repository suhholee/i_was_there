import SwiftUI
import SwiftData

struct ProfileOnboardingView: View {
    let userId: UUID
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Step = .displayName
    @State private var displayName = ""
    @State private var mlbFavoriteID = 0
    @State private var kboFavoriteID = 0

    private enum Step: Int, CaseIterable {
        case displayName
        case mlbTeam
        case kboTeam
        case favoritePlayers

        var title: String {
            switch self {
            case .displayName: "What should we call you?"
            case .mlbTeam: "Pick an MLB favorite"
            case .kboTeam: "Pick a KBO favorite"
            case .favoritePlayers: "Pick favorite players"
            }
        }

        var subtitle: String {
            switch self {
            case .displayName:
                "This shows on your Home screen. You can change it anytime in Settings."
            case .mlbTeam:
                "Track wins, losses, and leaders for your MLB team. Skip if you only follow KBO."
            case .kboTeam:
                "Same for the KBO diary. Skip if you only follow MLB."
            case .favoritePlayers:
                "Star players from your favorite teams. Their stats show on Home above team leaders."
            }
        }

        var primaryButtonTitle: String {
            switch self {
            case .displayName, .mlbTeam, .kboTeam: "Continue"
            case .favoritePlayers: "Get started"
            }
        }

        var next: Step? {
            Step(rawValue: rawValue + 1)
        }
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
        ZStack {
            StadiumAuthBackground()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.horizontal, 28)
                    .padding(.top, 16)

                Spacer(minLength: 24)

                VStack(spacing: 22) {
                    stepHeader

                    stepContent
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)

                    actionButtons
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 32)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ensureProfile()
            loadFromProfile()
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? DesignTokens.accent : DesignTokens.surface.opacity(0.7))
                    .frame(height: 4)
            }
        }
    }

    private var stepHeader: some View {
        VStack(spacing: 10) {
            Text(step.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.primaryText)
                .multilineTextAlignment(.center)

            Text(step.subtitle)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .displayName:
            displayNameField
        case .mlbTeam:
            teamPicker(
                selection: $mlbFavoriteID,
                teams: orderedMLBTeams,
                noneLabel: "No MLB team"
            )
        case .kboTeam:
            teamPicker(
                selection: $kboFavoriteID,
                teams: orderedKBOTeams,
                noneLabel: "No KBO team"
            )
        case .favoritePlayers:
            if let profile = profiles.first {
                FavoritePlayerOnboardingSearchView(
                    profile: profile,
                    mlbTeamID: mlbFavoriteID,
                    kboTeamID: kboFavoriteID
                )
            }
        }
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)

            ZStack(alignment: .leading) {
                if displayName.isEmpty {
                    Text("e.g. Alex")
                        .font(.body)
                        .foregroundStyle(placeholderColor)
                        .allowsHitTesting(false)
                }

                TextField("", text: $displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .font(.body)
            .foregroundStyle(DesignTokens.primaryText)
            .tint(DesignTokens.primaryText)
            .padding(12)
            .background(DesignTokens.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func teamPicker(
        selection: Binding<Int>,
        teams: [MLBTeamInfo],
        noneLabel: String
    ) -> some View {
        teamPickerContent(
            selection: selection,
            noneLabel: noneLabel,
            options: teams.map { team in
                (
                    id: team.id,
                    label: MLBTeamCatalog.pickerLabel(
                        for: team,
                        favoriteID: selection.wrappedValue == 0 ? nil : selection.wrappedValue
                    )
                )
            }
        )
    }

    private func teamPicker(
        selection: Binding<Int>,
        teams: [KBOTeamInfo],
        noneLabel: String
    ) -> some View {
        teamPickerContent(
            selection: selection,
            noneLabel: noneLabel,
            options: teams.map { team in
                (
                    id: team.id,
                    label: KBOTeamCatalog.pickerLabel(
                        for: team,
                        favoriteID: selection.wrappedValue == 0 ? nil : selection.wrappedValue
                    )
                )
            }
        )
    }

    private func teamPickerContent(
        selection: Binding<Int>,
        noneLabel: String,
        options: [(id: Int, label: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorite team")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)

            Menu {
                Button(noneLabel) {
                    selection.wrappedValue = 0
                }
                ForEach(options, id: \.id) { option in
                    Button(option.label) {
                        selection.wrappedValue = option.id
                    }
                }
            } label: {
                HStack {
                    Text(selectedTeamLabel(selection: selection.wrappedValue, noneLabel: noneLabel, options: options))
                        .foregroundStyle(DesignTokens.primaryText)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText)
                }
                .font(.body)
                .padding(12)
                .background(DesignTokens.surface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func selectedTeamLabel(
        selection: Int,
        noneLabel: String,
        options: [(id: Int, label: String)]
    ) -> String {
        guard selection != 0 else { return noneLabel }
        return options.first(where: { $0.id == selection })?.label ?? noneLabel
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: advanceSavingCurrentStep) {
                Text(step.primaryButtonTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: DesignTokens.accent.opacity(0.35), radius: 10, y: 4)
            }

            Button(action: skipCurrentStep) {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private var placeholderColor: Color {
        DesignTokens.secondaryText.opacity(0.85)
    }

    private func advanceSavingCurrentStep() {
        switch step {
        case .displayName:
            saveDisplayName()
        case .mlbTeam:
            saveMLBTeam()
        case .kboTeam:
            saveKBOTeam()
        case .favoritePlayers:
            finishOnboarding()
            return
        }

        if let next = step.next {
            step = next
        }
    }

    private func skipCurrentStep() {
        if step == .favoritePlayers {
            finishOnboarding()
        } else if let next = step.next {
            step = next
        }
    }

    private func finishOnboarding() {
        AuthSession.shared.clearProfileOnboarding()
        try? modelContext.save()
        CloudSyncTrigger.profile(modelContext: modelContext)
        onComplete()
    }

    private func saveDisplayName() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        profile.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveMLBTeam() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        if mlbFavoriteID == 0 {
            profile.setFavoriteTeam(id: nil, abbr: nil, for: .mlb)
        } else if let team = MLBTeamCatalog.team(id: mlbFavoriteID) {
            profile.setFavoriteTeam(id: team.id, abbr: team.abbreviation, for: .mlb)
        }
    }

    private func saveKBOTeam() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        if kboFavoriteID == 0 {
            profile.setFavoriteTeam(id: nil, abbr: nil, for: .kbo)
        } else if let team = KBOTeamCatalog.team(id: kboFavoriteID) {
            profile.setFavoriteTeam(id: team.id, abbr: team.abbreviation, for: .kbo)
        }
    }

    private func loadFromProfile() {
        guard let profile = profiles.first else { return }
        displayName = profile.displayName
        mlbFavoriteID = profile.favoriteTeamID ?? 0
        kboFavoriteID = profile.favoriteKBOTeamID ?? 0
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }
}

#Preview {
    ProfileOnboardingView(userId: UUID(), onComplete: {})
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
