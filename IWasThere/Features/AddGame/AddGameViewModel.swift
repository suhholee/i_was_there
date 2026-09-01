import Foundation
import SwiftData
import SwiftUI
import PhotosUI
import UIKit

@MainActor
final class AddGameViewModel: ObservableObject {
    @Published var step: AddGameStep = .date
    @Published var selectedDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @Published var mlbGames: [MLBScheduleGame] = []
    @Published var kboGames: [KBOScheduleGame] = []
    @Published var selectedMLBGame: MLBScheduleGame?
    @Published var selectedKBOGame: KBOScheduleGame?
    @Published var eventTitle: String = ""
    @Published var friendNames: [String] = []
    @Published var note: String = ""
    @Published var photoItems: [PhotosPickerItem] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    let league: League

    private let mlbClient: MLBClient
    private let kboClient: KBOClient

    init(
        league: League,
        mlbClient: MLBClient = .shared,
        kboClient: KBOClient = .shared
    ) {
        self.league = league
        self.mlbClient = mlbClient
        self.kboClient = kboClient
    }

    var findGamesButtonTitle: String {
        switch league {
        case .mlb: "Find MLB games"
        case .kbo: "Find KBO games"
        }
    }

    var selectedMatchupLabel: String? {
        switch league {
        case .mlb: selectedMLBGame?.matchupLabel
        case .kbo: selectedKBOGame?.matchupLabel
        }
    }

    var canContinueToDiary: Bool {
        switch league {
        case .mlb:
            guard let game = selectedMLBGame else { return false }
            return game.isFinal
        case .kbo:
            guard let game = selectedKBOGame else { return false }
            return game.isFinal
        }
    }

    func loadSchedule() async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        mlbGames = []
        kboGames = []
        selectedMLBGame = nil
        selectedKBOGame = nil
        defer { isLoading = false }

        do {
            switch league {
            case .mlb:
                let response = try await mlbClient.schedule(date: selectedDate)
                let all = response.dates.flatMap(\.games)
                mlbGames = all.sorted { $0.gamePk < $1.gamePk }
                if mlbGames.isEmpty {
                    infoMessage = "No MLB games on this date."
                } else if mlbGames.allSatisfy({ !$0.isFinal }) {
                    infoMessage = "Games found, but none are Final yet. Pick a completed game."
                }
            case .kbo:
                let year = Calendar.current.component(.year, from: selectedDate)
                if year < League.kbo.earliestImportSeason {
                    infoMessage = "KBO box scores are reliable from \(YearFormat.string(League.kbo.earliestImportSeason)) onward. Pick a later date."
                    step = .match
                    return
                }
                let all = try await kboClient.schedule(date: selectedDate)
                kboGames = all
                if kboGames.isEmpty {
                    infoMessage = "No KBO games on this date."
                } else if kboGames.allSatisfy({ !$0.isFinal }) {
                    infoMessage = "Games found, but none are Final yet. Pick a completed game."
                }
            }
            step = .match
        } catch {
            errorMessage = "Could not load schedule. \(error.localizedDescription)"
        }
    }

    func goToDiary() {
        switch league {
        case .mlb:
            guard let selectedMLBGame, selectedMLBGame.isFinal else {
                errorMessage = GameImportError.notFinal.localizedDescription
                return
            }
        case .kbo:
            guard let selectedKBOGame, selectedKBOGame.isFinal else {
                errorMessage = GameImportError.notFinal.localizedDescription
                return
            }
        }
        step = .diary
    }

    func save(
        modelContext: ModelContext,
        existingGamePks: Set<Int>,
        existingGameKeys: Set<String>
    ) async -> AttendedGame? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let attended: AttendedGame
            switch league {
            case .mlb:
                guard let selectedMLBGame else {
                    errorMessage = "Select a game first."
                    return nil
                }
                guard selectedMLBGame.isFinal else {
                    errorMessage = GameImportError.notFinal.localizedDescription
                    return nil
                }
                let boxscore = try await mlbClient.boxscore(gamePk: selectedMLBGame.gamePk)
                attended = try BoxscoreImporter.makeAttendedGame(
                    from: selectedMLBGame,
                    boxscore: boxscore,
                    existingGamePks: existingGamePks
                )
            case .kbo:
                guard let selectedKBOGame else {
                    errorMessage = "Select a game first."
                    return nil
                }
                guard selectedKBOGame.isFinal else {
                    errorMessage = GameImportError.notFinal.localizedDescription
                    return nil
                }
                let payload = try await kboClient.boxPayload(game: selectedKBOGame)
                attended = try KBOBoxscoreImporter.makeAttendedGame(
                    from: payload,
                    existingGameKeys: existingGameKeys
                )
            }

            attended.eventTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            attended.note = note.trimmingCharacters(in: .whitespacesAndNewlines)

            modelContext.insert(attended)
            for stat in attended.playerStats {
                stat.game = attended
            }
            GameFriendStore.setFriends(names: friendNames, on: attended, modelContext: modelContext)
            try modelContext.save()

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
