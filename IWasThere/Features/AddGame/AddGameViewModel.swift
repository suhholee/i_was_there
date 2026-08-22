import Foundation
import SwiftData
import SwiftUI
import PhotosUI
import UIKit

@MainActor
final class AddGameViewModel: ObservableObject {
    @Published var step: AddGameStep = .date
    @Published var selectedDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @Published var games: [MLBScheduleGame] = []
    @Published var selectedGame: MLBScheduleGame?
    @Published var eventTitle: String = ""
    @Published var companions: String = ""
    @Published var note: String = ""
    @Published var photoItems: [PhotosPickerItem] = []
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

    func goToDiary() {
        guard let selectedGame, selectedGame.isFinal else {
            errorMessage = GameImportError.notFinal.localizedDescription
            return
        }
        step = .diary
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
            attended.eventTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            attended.companions = companions.trimmingCharacters(in: .whitespacesAndNewlines)
            attended.note = note.trimmingCharacters(in: .whitespacesAndNewlines)

            // Persist the game first so the Games list updates even if photo import fails.
            modelContext.insert(attended)
            for stat in attended.playerStats {
                modelContext.insert(stat)
            }
            try modelContext.save()

            // Best-effort photos — never block the saved game.
            for item in photoItems {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = PhotoStore.jpegData(from: image)
                    else { continue }
                    let relative = try PhotoStore.saveJPEG(jpeg, gamePk: attended.mlbGamePk)
                    let photo = GamePhoto(relativePath: relative)
                    photo.game = attended
                    modelContext.insert(photo)
                    attended.photos.append(photo)
                } catch {
                    continue
                }
            }
            try? modelContext.save()
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
    case diary
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
