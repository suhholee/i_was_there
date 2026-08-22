import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct GameDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Bindable var game: AttendedGame

    @State private var lineSegment: LineSegment = .batters
    @State private var batterSort: BatterSortKey = .ops
    @State private var pitcherSort: PitcherSortKey = .ip
    /// `false` = High → Low (descending), `true` = Low → High (ascending)
    @State private var sortAscending = false
    @State private var newPhotoItems: [PhotosPickerItem] = []

    private var favoriteTeamID: Int? { profiles.first?.favoriteTeamID }

    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    diarySection
                    photoSection
                    linesSection
                }
                .padding(16)
            }
        }
        .navigationTitle("Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DesignTokens.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    for photo in game.photos {
                        PhotoStore.delete(relativePath: photo.relativePath)
                    }
                    modelContext.delete(game)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .onChange(of: lineSegment) { _, _ in
            sortAscending = false
            if lineSegment == .batters {
                batterSort = .ops
            } else {
                pitcherSort = .ip
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(game.awayTeamName) @ \(game.homeTeamName)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.cardPrimaryText)
                Spacer(minLength: 8)
                if game.favoriteTeamWon(favoriteTeamID: favoriteTeamID) == true {
                    Text("WIN")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(DesignTokens.winGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DesignTokens.winGreen.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text("\(game.awayScore)–\(game.homeScore)")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(DesignTokens.accent)
            Text(game.gameDate.formatted(date: .complete, time: .omitted))
                .foregroundStyle(DesignTokens.cardSecondaryText)
            if !game.venueName.isEmpty {
                Text(game.venueName)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            if !game.eventTitle.isEmpty {
                Text(game.eventTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
            }
            if !game.companions.isEmpty {
                Text("w/ \(game.companions)")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var diarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diary")
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            diaryEditor(title: "Event / giveaway", text: $game.eventTitle)
            diaryEditor(title: "Companions", text: $game.companions)
            diaryEditor(title: "Notes", text: $game.note)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: game.eventTitle) { _, _ in persistDiary() }
        .onChange(of: game.companions) { _, _ in persistDiary() }
        .onChange(of: game.note) { _, _ in persistDiary() }
    }

    private func diaryEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            TextField(title, text: text, axis: .vertical)
                .padding(10)
                .background(DesignTokens.cardBackground)
                .foregroundStyle(DesignTokens.cardPrimaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .lineLimit(2...5)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)
                Spacer()
                PhotosPicker(
                    selection: $newPhotoItems,
                    maxSelectionCount: 8,
                    matching: .images
                ) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .onChange(of: newPhotoItems) { _, items in
                    Task { await importPhotos(items) }
                }
            }

            if game.photos.isEmpty {
                Text("No photos yet.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(game.photos) { photo in
                        ZStack(alignment: .topTrailing) {
                            GamePhotoThumbnail(relativePath: photo.relativePath)
                                .frame(height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button {
                                deletePhoto(photo)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(4)
                            }
                        }
                    }
                }
            }
        }
    }

    private func persistDiary() {
        try? modelContext.save()
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let jpeg = PhotoStore.jpegData(from: image),
               let relative = try? PhotoStore.saveJPEG(jpeg, gamePk: game.mlbGamePk) {
                let photo = GamePhoto(relativePath: relative)
                photo.game = game
                game.photos.append(photo)
            }
        }
        newPhotoItems = []
        try? modelContext.save()
    }

    private func deletePhoto(_ photo: GamePhoto) {
        PhotoStore.delete(relativePath: photo.relativePath)
        game.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
        modelContext.delete(photo)
        try? modelContext.save()
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attendance-scoped lines")
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)

            Picker("Lines", selection: $lineSegment) {
                ForEach(LineSegment.allCases) { segment in
                    Text(segment.title).tag(segment)
                }
            }
            .pickerStyle(.segmented)

            sortControls

            LazyVStack(spacing: 10) {
                ForEach(displayedStats) { stat in
                    playerCard(stat)
                }
            }
        }
    }

    private var sortControls: some View {
        HStack(spacing: 12) {
            if lineSegment == .batters {
                Picker("Sort", selection: $batterSort) {
                    ForEach(BatterSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignTokens.primaryText)
                .labelsHidden()
            } else {
                Picker("Sort", selection: $pitcherSort) {
                    ForEach(PitcherSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .tint(DesignTokens.primaryText)
                .labelsHidden()
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    sortAscending = true
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(sortAscending ? DesignTokens.accent : DesignTokens.primaryText)
                        .frame(width: 36, height: 32)
                        .background(sortAscending ? DesignTokens.accent.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort low to high")

                Button {
                    sortAscending = false
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(!sortAscending ? DesignTokens.accent : DesignTokens.primaryText)
                        .frame(width: 36, height: 32)
                        .background(!sortAscending ? DesignTokens.accent.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort high to low")
            }
            .padding(4)
            .background(DesignTokens.background.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var displayedStats: [GamePlayerStat] {
        let base: [GamePlayerStat]
        switch lineSegment {
        case .batters:
            base = game.playerStats.filter { $0.plateAppearances > 0 || $0.atBats > 0 }
        case .pitchers:
            base = game.playerStats.filter(\.isPitcher)
        }

        return base.sorted { lhs, rhs in
            switch lineSegment {
            case .batters:
                return compareBatter(lhs, rhs, by: batterSort, ascending: sortAscending)
            case .pitchers:
                return comparePitcher(lhs, rhs, by: pitcherSort, ascending: sortAscending)
            }
        }
    }

    private func compareBatter(
        _ lhs: GamePlayerStat,
        _ rhs: GamePlayerStat,
        by key: BatterSortKey,
        ascending: Bool
    ) -> Bool {
        let left: Double
        let right: Double
        switch key {
        case .avg: left = lhs.battingAverage ?? -1; right = rhs.battingAverage ?? -1
        case .obp: left = lhs.onBasePercentage ?? -1; right = rhs.onBasePercentage ?? -1
        case .slg: left = lhs.slugging ?? -1; right = rhs.slugging ?? -1
        case .ops: left = lhs.ops ?? -1; right = rhs.ops ?? -1
        case .hr: left = Double(lhs.homeRuns); right = Double(rhs.homeRuns)
        case .rbi: left = Double(lhs.rbi); right = Double(rhs.rbi)
        case .h: left = Double(lhs.hits); right = Double(rhs.hits)
        case .ab: left = Double(lhs.atBats); right = Double(rhs.atBats)
        case .bb: left = Double(lhs.walks); right = Double(rhs.walks)
        }
        if left == right {
            return lhs.playerName < rhs.playerName
        }
        return ascending ? left < right : left > right
    }

    private func comparePitcher(
        _ lhs: GamePlayerStat,
        _ rhs: GamePlayerStat,
        by key: PitcherSortKey,
        ascending: Bool
    ) -> Bool {
        let left: Double
        let right: Double
        switch key {
        case .era: left = lhs.era ?? 999; right = rhs.era ?? 999
        case .whip: left = lhs.whip ?? 999; right = rhs.whip ?? 999
        case .k: left = Double(lhs.strikeouts); right = Double(rhs.strikeouts)
        case .ip: left = Double(lhs.inningsPitchedOuts); right = Double(rhs.inningsPitchedOuts)
        case .er: left = Double(lhs.earnedRuns); right = Double(rhs.earnedRuns)
        case .bb: left = Double(lhs.walksAllowed); right = Double(rhs.walksAllowed)
        case .h: left = Double(lhs.hitsAllowed); right = Double(rhs.hitsAllowed)
        }
        if left == right {
            return lhs.playerName < rhs.playerName
        }
        return ascending ? left < right : left > right
    }

    private func playerCard(_ stat: GamePlayerStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.jerseyNumber.isEmpty ? "#" : "#\(stat.jerseyNumber)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(DesignTokens.accent)
                Text(stat.playerName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.cardPrimaryText)
                Spacer()
                Text(stat.position)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }

            if lineSegment == .batters {
                Text(
                    "\(stat.hits)-\(stat.atBats) · HR \(stat.homeRuns) · RBI \(stat.rbi) · BB \(stat.walks)"
                )
                .font(.subheadline)
                .foregroundStyle(DesignTokens.cardSecondaryText)
                Text(
                    "AVG \(StatFormulas.formatAverage(stat.battingAverage)) · OBP \(StatFormulas.formatAverage(stat.onBasePercentage)) · SLG \(StatFormulas.formatAverage(stat.slugging)) · OPS \(StatFormulas.formatAverage(stat.ops))"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.cardPrimaryText)
            } else {
                Text(
                    "IP \(StatFormulas.formatIP(outs: stat.inningsPitchedOuts)) · ER \(stat.earnedRuns) · K \(stat.strikeouts) · BB \(stat.walksAllowed) · H \(stat.hitsAllowed)"
                )
                .font(.subheadline)
                .foregroundStyle(DesignTokens.cardSecondaryText)
                Text(
                    "ERA \(StatFormulas.formatRate(stat.era, digits: 2)) · WHIP \(StatFormulas.formatRate(stat.whip, digits: 2))"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(DesignTokens.cardPrimaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum LineSegment: String, CaseIterable, Identifiable {
    case batters
    case pitchers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .batters: "Batters"
        case .pitchers: "Pitchers"
        }
    }
}

private enum BatterSortKey: String, CaseIterable, Identifiable {
    case ops, avg, obp, slg, hr, rbi, h, ab, bb
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ops: "OPS"
        case .avg: "AVG"
        case .obp: "OBP"
        case .slg: "SLG"
        case .hr: "HR"
        case .rbi: "RBI"
        case .h: "H"
        case .ab: "AB"
        case .bb: "BB"
        }
    }
}

private enum PitcherSortKey: String, CaseIterable, Identifiable {
    case ip, era, whip, k, er, bb, h
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ip: "IP"
        case .era: "ERA"
        case .whip: "WHIP"
        case .k: "K"
        case .er: "ER"
        case .bb: "BB"
        case .h: "H"
        }
    }
}

#Preview {
    let game = AttendedGame(
        mlbGamePk: 1,
        gameDate: .now,
        season: 2024,
        venueName: "Dodger Stadium",
        homeTeamID: 119,
        awayTeamID: 147,
        homeTeamName: "Los Angeles Dodgers",
        awayTeamName: "New York Yankees",
        homeScore: 6,
        awayScore: 3,
        homeWon: true,
        awayWon: false,
        playerStats: [
            GamePlayerStat(
                playerID: 1,
                playerName: "Freddie Freeman",
                jerseyNumber: "5",
                teamID: 119,
                position: "1B",
                isPitcher: false,
                atBats: 5,
                hits: 2,
                homeRuns: 1,
                rbi: 4,
                walks: 0,
                totalBases: 7,
                plateAppearances: 5
            )
        ]
    )
    return NavigationStack {
        GameDetailView(game: game)
    }
    .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
