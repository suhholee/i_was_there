import SwiftUI
import SwiftData

struct AddGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingGames: [AttendedGame]

    @StateObject private var viewModel = AddGameViewModel()
    var onSaved: ((AttendedGame) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepHeader
                Divider()
                content
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Add game")
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
        HStack(spacing: 12) {
            stepChip(number: 1, title: "Date", active: viewModel.step == .date)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(DesignTokens.secondaryText)
            stepChip(number: 2, title: "Match", active: viewModel.step == .match)
        }
        .padding()
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
        }
    }

    private var dateStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("When did you go?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.primaryText)

            DatePicker(
                "Game date",
                selection: $viewModel.selectedDate,
                in: ...Date.now,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(DesignTokens.accent)
            .colorScheme(.dark)

            Spacer()

            Button {
                Task { await viewModel.loadSchedule() }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Find MLB games")
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

            if let info = viewModel.infoMessage {
                Text(info)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.secondaryText)
            }

            if viewModel.isLoading {
                ProgressView("Loading schedule…")
                    .tint(DesignTokens.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.games, id: \.gamePk) { game in
                    Button {
                        viewModel.selectedGame = game
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: viewModel.selectedGame?.gamePk == game.gamePk ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.selectedGame?.gamePk == game.gamePk ? DesignTokens.accent : DesignTokens.secondaryText)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.matchupLabel)
                                    .font(.headline)
                                    .foregroundStyle(DesignTokens.primaryText)
                                Text("\(game.scoreLabel) · \(game.status.detailedState)")
                                    .font(.subheadline)
                                    .foregroundStyle(DesignTokens.secondaryText)
                                if let venue = game.venue?.name {
                                    Text(venue)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.secondaryText)
                                }
                                if !game.isFinal {
                                    Text("Not final — can’t import box score yet")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!game.isFinal)
                    .listRowBackground(DesignTokens.surface)
                }
                .scrollContentBackground(.hidden)
            }

            Button {
                Task {
                    let existing = Set(existingGames.map(\.mlbGamePk))
                    if let saved = await viewModel.save(modelContext: modelContext, existingGamePks: existing) {
                        onSaved?(saved)
                        dismiss()
                    }
                }
            } label: {
                HStack {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Save to my log")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSave ? DesignTokens.accent : DesignTokens.surface)
                .foregroundStyle(canSave ? Color.white : DesignTokens.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!canSave || viewModel.isSaving)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
    }

    private var canSave: Bool {
        guard let game = viewModel.selectedGame else { return false }
        return game.isFinal
    }
}

#Preview {
    AddGameView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
