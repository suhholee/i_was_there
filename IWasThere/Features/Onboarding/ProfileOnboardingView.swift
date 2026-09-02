import SwiftUI
import SwiftData

struct ProfileOnboardingView: View {
    let userId: UUID
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Step = .username
    @State private var username = ""
    @State private var usernameStatus: UsernameStatus = .idle
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var avatarImage: UIImage?
    @State private var profileVisibility: ProfileVisibility = .public
    @State private var displayName = ""
    @State private var mlbFavoriteID = 0
    @State private var kboFavoriteID = 0
    @State private var isAdvancing = false

    private enum Step: Int, CaseIterable {
        case username
        case avatar
        case visibility
        case displayName
        case mlbTeam
        case kboTeam
        case favoritePlayers

        var title: String {
            switch self {
            case .username: "Choose your username"
            case .avatar: "Add a profile photo"
            case .visibility: "Who can see your games?"
            case .displayName: "What should we call you?"
            case .mlbTeam: "Pick an MLB favorite"
            case .kboTeam: "Pick a KBO favorite"
            case .favoritePlayers: "Pick favorite players"
            }
        }

        var subtitle: String {
            switch self {
            case .username:
                "Your @tag is unique and how friends find you. You can change it later in Settings."
            case .avatar:
                "Optional — add a photo now or skip and upload one anytime in Settings."
            case .visibility:
                "You can switch between public and private anytime in Settings."
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
            case .favoritePlayers: "Get started"
            default: "Continue"
            }
        }

        var next: Step? {
            Step(rawValue: rawValue + 1)
        }

        var allowsSkip: Bool {
            self != .username
        }
    }

    private enum UsernameStatus: Equatable {
        case idle
        case checking
        case available
        case unavailable
        case invalid(String)
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

    private var canContinueFromUsername: Bool {
        usernameStatus == .available
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
        .onChange(of: username) { _, newValue in
            scheduleUsernameCheck(for: newValue)
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
        case .username:
            usernameField
        case .avatar:
            ProfileAvatarPicker(image: $avatarImage)
        case .visibility:
            visibilityPicker
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

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Username")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)

            HStack(spacing: 8) {
                Text("@")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)

                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(DesignTokens.primaryText)
            }
            .padding(12)
            .background(DesignTokens.surface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Group {
                switch usernameStatus {
                case .idle:
                    Text("Letters, numbers, and underscores only.")
                case .checking:
                    Text("Checking availability…")
                case .available:
                    Text("@\(UsernameRules.normalize(username)) is available.")
                        .foregroundStyle(DesignTokens.winGreen)
                case .unavailable:
                    Text("That username is taken.")
                        .foregroundStyle(DesignTokens.loseRed)
                case .invalid(let message):
                    Text(message)
                        .foregroundStyle(DesignTokens.loseRed)
                }
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.secondaryText)
        }
    }

    private var visibilityPicker: some View {
        VStack(spacing: 12) {
            ForEach(ProfileVisibility.allCases) { option in
                Button {
                    profileVisibility = option
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: profileVisibility == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(profileVisibility == option ? DesignTokens.accent : DesignTokens.secondaryText)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.primaryText)
                            Text(option.subtitle)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.secondaryText)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(DesignTokens.surface.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
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
            Button {
                Task { await advanceSavingCurrentStep() }
            } label: {
                HStack {
                    if isAdvancing {
                        ProgressView().tint(.white)
                    }
                    Text(step.primaryButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(primaryButtonEnabled ? DesignTokens.accent : DesignTokens.surface)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: DesignTokens.accent.opacity(primaryButtonEnabled ? 0.35 : 0), radius: 10, y: 4)
            }
            .disabled(!primaryButtonEnabled || isAdvancing)

            if step.allowsSkip {
                Button(action: skipCurrentStep) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                }
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private var primaryButtonEnabled: Bool {
        switch step {
        case .username:
            return canContinueFromUsername
        default:
            return true
        }
    }

    private var placeholderColor: Color {
        DesignTokens.secondaryText.opacity(0.85)
    }

    private func scheduleUsernameCheck(for raw: String) {
        usernameCheckTask?.cancel()

        if let message = UsernameRules.validationMessage(for: raw) {
            usernameStatus = .invalid(message)
            return
        }

        usernameStatus = .checking
        let normalized = UsernameRules.normalize(raw)
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let available = await UsernameAvailabilityService.shared.isAvailable(normalized)
            guard !Task.isCancelled else { return }
            usernameStatus = available ? .available : .unavailable
        }
    }

    private func advanceSavingCurrentStep() async {
        isAdvancing = true
        defer { isAdvancing = false }

        switch step {
        case .username:
            guard canContinueFromUsername else { return }
            saveUsername()
        case .avatar:
            saveAvatar()
        case .visibility:
            saveVisibility()
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

    private func saveUsername() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        profile.setUsername(username)
    }

    private func saveAvatar() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        try? ProfileAvatarPersistence.apply(image: avatarImage, to: profile)
    }

    private func saveVisibility() {
        ensureProfile()
        guard let profile = profiles.first else { return }
        profile.visibility = profileVisibility
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
        username = profile.username
        if !username.isEmpty {
            scheduleUsernameCheck(for: username)
        }
        avatarImage = ProfileAvatarPersistence.loadImage(for: profile)
        profileVisibility = profile.visibility
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
