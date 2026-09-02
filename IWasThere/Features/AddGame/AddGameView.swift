import SwiftUI
import SwiftData
import PhotosUI

struct AddGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingGames: [AttendedGame]
    @Query private var profiles: [UserProfile]

    @StateObject private var viewModel: AddGameViewModel
    @State private var isPickingMonthYear = false
    @State private var draftMonth = Calendar.current.component(.month, from: .now)
    @State private var draftYear = Calendar.current.component(.year, from: .now)
    var onSaved: ((AttendedGame) -> Void)?

    init(league: League? = nil, onSaved: ((AttendedGame) -> Void)? = nil) {
        let resolved = league ?? .mlb
        _viewModel = StateObject(wrappedValue: AddGameViewModel(league: resolved))
        self.onSaved = onSaved
    }

    private var activeLeague: League {
        profiles.first?.league ?? viewModel.league
    }

    private var leagueGames: [AttendedGame] {
        existingGames.filter { $0.resolvedLeague == viewModel.league }
    }

    private var existingGamePks: Set<Int> {
        Set(leagueGames.map(\.mlbGamePk))
    }

    private var existingGameKeys: Set<String> {
        Set(leagueGames.map { game in
            if !game.gameKey.isEmpty { return game.gameKey }
            if game.resolvedLeague == .kbo, !game.kboGameID.isEmpty {
                return LeagueKey.kbo(game.kboGameID)
            }
            return LeagueKey.mlb(game.mlbGamePk)
        })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepHeader
                Divider().overlay(DesignTokens.surface)
                content
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Add \(viewModel.league.title) game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var stepHeader: some View {
        HStack(spacing: 8) {
            stepChip(number: 1, title: "Date", active: viewModel.step == .date)
            chevron
            stepChip(number: 2, title: "Match", active: viewModel.step == .match)
            chevron
            stepChip(number: 3, title: "Diary", active: viewModel.step == .diary)
        }
        .padding()
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(DesignTokens.secondaryText)
    }

    private func stepChip(number: Int, title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(active ? DesignTokens.accent : DesignTokens.surface)
                .clipShape(Circle())
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
        }
        .foregroundStyle(DesignTokens.primaryText)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .date:
            dateStep
        case .match:
            matchStep
        case .diary:
            diaryStep
        }
    }

    private var dateStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("When did you go?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText)

                if viewModel.league == .kbo {
                    YearFormat.verbatim(
                        "Box scores work best from %@ onward.",
                        year: League.kbo.earliestImportSeason
                    )
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.secondaryText)
                }

            GameDatePicker(
                selectedDate: $viewModel.selectedDate,
                isPickingMonthYear: $isPickingMonthYear,
                draftMonth: $draftMonth,
                draftYear: $draftYear
            )

            Spacer()

            Button {
                if isPickingMonthYear {
                    GameDatePicker.applyMonthYear(
                        selectedDate: &viewModel.selectedDate,
                        draftMonth: draftMonth,
                        draftYear: draftYear
                    )
                    isPickingMonthYear = false
                } else {
                    Task { await viewModel.loadSchedule() }
                }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    }
                    Text(isPickingMonthYear ? "Select month" : viewModel.findGamesButtonTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(DesignTokens.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(viewModel.isLoading)
        }
        .padding()
        .onAppear {
            GameDatePicker.syncDraft(
                from: viewModel.selectedDate,
                draftMonth: &draftMonth,
                draftYear: &draftYear
            )
            _ = activeLeague
        }
    }

    private var matchStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    viewModel.step = .date
                } label: {
                    Label("Change date", systemImage: "calendar")
                }
                Spacer()
                Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(DesignTokens.secondaryText)
            }
            .padding(.horizontal)

            if let info = viewModel.infoMessage {
                Text(verbatim: info)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.secondaryText)
                    .padding(.horizontal)
            }

            if let error = viewModel.errorMessage, viewModel.step == .match {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.loseRed)
                    .padding(.horizontal)
            }

            if viewModel.isLoading {
                ProgressView("Loading schedule…")
                    .tint(DesignTokens.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.league == .mlb {
                mlbMatchList
            } else {
                kboMatchList
            }

            Button {
                viewModel.goToDiary()
            } label: {
                Text("Next: Diary")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canContinueToDiary ? DesignTokens.accent : DesignTokens.surface)
                    .foregroundStyle(canContinueToDiary ? Color.white : DesignTokens.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!canContinueToDiary)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
    }

    private var mlbMatchList: some View {
        Group {
            if viewModel.mlbGames.isEmpty {
                emptyMatchState
            } else {
                List(viewModel.mlbGames, id: \.gamePk) { game in
                    let alreadyLogged = existingGamePks.contains(game.gamePk)
                    Button {
                        guard !alreadyLogged else { return }
                        viewModel.selectedMLBGame = game
                    } label: {
                        matchRow(
                            selected: viewModel.selectedMLBGame?.gamePk == game.gamePk,
                            alreadyLogged: alreadyLogged,
                            matchup: game.matchupLabel,
                            detail: "\(game.scoreLabel) · \(game.status.detailedState)",
                            venue: game.venue?.name,
                            isFinal: game.isFinal
                        )
                    }
                    .disabled(!game.isFinal || alreadyLogged)
                    .listRowBackground(DesignTokens.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var kboMatchList: some View {
        Group {
            if viewModel.kboGames.isEmpty {
                emptyMatchState
            } else {
                List(viewModel.kboGames) { game in
                    let key = LeagueKey.kbo(game.gameID)
                    let alreadyLogged = existingGameKeys.contains(key)
                    Button {
                        guard !alreadyLogged else { return }
                        viewModel.selectedKBOGame = game
                    } label: {
                        matchRow(
                            selected: viewModel.selectedKBOGame?.gameID == game.gameID,
                            alreadyLogged: alreadyLogged,
                            matchup: game.matchupLabel,
                            detail: game.isFinal ? "Final" : "Not final",
                            venue: nil,
                            isFinal: game.isFinal
                        )
                    }
                    .disabled(!game.isFinal || alreadyLogged)
                    .listRowBackground(DesignTokens.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyMatchState: some View {
        ContentUnavailableView(
            "No games found",
            systemImage: "calendar.badge.exclamationmark",
                    description: Text(verbatim: viewModel.infoMessage ?? "Try another date.")
        )
        .foregroundStyle(DesignTokens.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func matchRow(
        selected: Bool,
        alreadyLogged: Bool,
        matchup: String,
        detail: String,
        venue: String?,
        isFinal: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(
                    alreadyLogged
                        ? DesignTokens.secondaryText.opacity(0.35)
                        : (selected ? DesignTokens.accent : DesignTokens.secondaryText)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(matchup)
                    .font(.headline)
                    .foregroundStyle(alreadyLogged ? DesignTokens.secondaryText : DesignTokens.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
                if let venue {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText)
                }
                if alreadyLogged {
                    Text("Already logged")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText)
                } else if !isFinal {
                    Text("Not final — can't import box score yet")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var diaryStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        viewModel.step = .match
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Spacer()
                    if let label = viewModel.selectedMatchupLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText)
                            .lineLimit(1)
                    }
                }

                Text("What made this night?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText)

                diaryField(title: "Event/Giveaway", text: $viewModel.eventTitle)
                FriendEditorView(friends: $viewModel.friendEntries, appearance: .addGameDiary)
                diaryField(title: "Notes", text: $viewModel.note)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Photos")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.primaryText)
                    PhotosPicker(
                        selection: $viewModel.photoItems,
                        maxSelectionCount: 12,
                        matching: .images
                    ) {
                        Label(
                            viewModel.photoItems.isEmpty
                                ? "Add photos"
                                : "\(viewModel.photoItems.count) photo\(viewModel.photoItems.count == 1 ? "" : "s") selected",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignTokens.surface)
                        .foregroundStyle(DesignTokens.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Button {
                    Task {
                        if let saved = await viewModel.save(
                            modelContext: modelContext,
                            existingGamePks: existingGamePks,
                            existingGameKeys: existingGameKeys
                        ) {
                            onSaved?(saved)
                            CloudSyncTrigger.game(saved, modelContext: modelContext)
                            Task {
                                try? await GameInviteService.shared.sendInvitesForNewLinkedFriends(
                                    on: saved,
                                    previousLinkedUserIds: [],
                                    modelContext: modelContext
                                )
                            }
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Complete")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DesignTokens.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.isSaving)
            }
            .padding()
        }
    }

    private func diaryField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText)
            TextField("", text: text, axis: .vertical)
                .padding(12)
                .background(DesignTokens.surface)
                .foregroundStyle(DesignTokens.primaryText)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .lineLimit(3...6)
        }
    }

    private var canContinueToDiary: Bool {
        guard viewModel.canContinueToDiary else { return false }
        switch viewModel.league {
        case .mlb:
            guard let game = viewModel.selectedMLBGame else { return false }
            return !existingGamePks.contains(game.gamePk)
        case .kbo:
            guard let game = viewModel.selectedKBOGame else { return false }
            return !existingGameKeys.contains(LeagueKey.kbo(game.gameID))
        }
    }
}

#Preview {
    AddGameView(league: .mlb)
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
