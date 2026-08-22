import Foundation
import SwiftData
import SwiftUI

@MainActor
final class AddGameViewModel: ObservableObject {
    @Published var step: AddGameStep = .date
    @Published var selectedDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @Published var games: [MLBScheduleGame] = []
    @Published var selectedGame: MLBScheduleGame?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let client: MLBClient

    init(client: MLBClient = .shared) {
        self.client = client
    }

    func loadSchedule() async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        games = []
        selectedGame = nil
        defer { isLoading = false }

        do {
            let response = try await client.schedule(date: selectedDate)
            let all = response.dates.flatMap(\.games)
            games = all.sorted { $0.gamePk < $1.gamePk }
            if games.isEmpty {
                infoMessage = "No MLB games on this date."
            } else if games.allSatisfy({ !$0.isFinal }) {
                infoMessage = "Games found, but none are Final yet. Pick a completed game."
            }
            step = .match
        } catch {
            errorMessage = "Could not load schedule. \(error.localizedDescription)"
        }
    }

    func save(
        modelContext: ModelContext,
        existingGamePks: Set<Int>
    ) async -> AttendedGame? {
        guard let selectedGame else {
            errorMessage = "Select a game first."
            return nil
        }
        guard selectedGame.isFinal else {
            errorMessage = GameImportError.notFinal.localizedDescription
            return nil
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let boxscore = try await client.boxscore(gamePk: selectedGame.gamePk)
            let attended = try BoxscoreImporter.makeAttendedGame(
                from: selectedGame,
                boxscore: boxscore,
                existingGamePks: existingGamePks
            )
            modelContext.insert(attended)
            try modelContext.save()
            return attended
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

enum AddGameStep: Int, CaseIterable {
    case date
    case match
}

extension MLBScheduleGame {
    var isFinal: Bool {
        status.abstractGameState == "Final" || status.detailedState == "Final"
    }

    var matchupLabel: String {
        "\(teams.away.team.name) @ \(teams.home.team.name)"
    }

    var scoreLabel: String {
        let away = teams.away.score.map(String.init) ?? "—"
        let home = teams.home.score.map(String.init) ?? "—"
        return "\(away)–\(home)"
    }
}
