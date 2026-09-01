import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct GameDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Bindable var game: AttendedGame

    @State private var detailTab: DetailTab = .diary
    @State private var isEditingDiary = false
    @State private var draftEventTitle = ""
    @State private var draftFriendNames: [String] = []
    @State private var draftNote = ""

    @State private var lineSegment: LineSegment = .batters
    @State private var batterSort: BatterSortKey = .ops
    @State private var pitcherSort: PitcherSortKey = .ip
    /// `false` = High → Low (descending), `true` = Low → High (ascending)
    @State private var sortAscending = false
    @State private var newPhotoItems: [PhotosPickerItem] = []
    @State private var enlargedPhotoPath: String?

    private var favoriteTeamID: Int? {
        let league = game.resolvedLeague
        return profiles.first?.favoriteTeamID(for: league)
    }

    private var batterLeaderCategory: LeaderboardEngine.BatterCategory {
        profiles.first?.homeBatterCategory(for: game.resolvedLeague)
            ?? (game.resolvedLeague == .kbo ? .avg : .ops)
    }

    private var pitcherLeaderCategory: LeaderboardEngine.PitcherCategory {
        profiles.first?.homePitcherCategory() ?? .era
    }

    private var scoreColor: Color {
        if let winnerID = game.winningTeamID {
            return TeamTheme.forTeamID(winnerID).primary
        }
        return DesignTokens.cardPrimaryText
    }

    var body: some View {
        ZStack {
            DesignTokens.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    let topBatter = LeaderboardEngine.gameLeaderBatter(
                        in: game,
                        category: batterLeaderCategory
                    )
                    let topPitcher = LeaderboardEngine.gameLeaderPitcher(
                        in: game,
                        category: pitcherLeaderCategory
                    )
                    if let batter = topBatter {
                        gameLeaderCard(batter, isPitcher: false, category: batterLeaderCategory)
                    }
                    if let pitcher = topPitcher {
                        gameLeaderCard(pitcher, isPitcher: true, category: pitcherLeaderCategory)
                    }

                    Picker("Section", selection: $detailTab) {
                        ForEach(DetailTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: detailTab) { _, tab in
                        if tab != .diary {
                            cancelDiaryEdit()
                        }
                    }

                    switch detailTab {
                    case .diary:
                        diaryTab
                    case .lines:
                        linesSection
                    }
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Delete game", role: .destructive) {
                        for photo in game.photos {
                            PhotoStore.delete(relativePath: photo.relativePath)
                        }
                        modelContext.delete(game)
                        try? modelContext.save()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
        .task {
            await StarterBackfill.ensureStarters(for: game, modelContext: modelContext)
        }
        .fullScreenCover(isPresented: Binding(
            get: { enlargedPhotoPath != nil },
            set: { if !$0 { enlargedPhotoPath = nil } }
        )) {
            if let path = enlargedPhotoPath {
                PhotoLightboxView(relativePath: path) {
                    enlargedPhotoPath = nil
                }
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
                FavoriteResultBadge(
                    won: game.favoriteTeamWon(favoriteTeamID: favoriteTeamID),
                    compact: false
                )
            }
            Text("\(game.awayScore)–\(game.homeScore)")
                .font(ScaledTypography.heroScore)
                .foregroundStyle(scoreColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(game.localDateTimeLabelLong)
                .foregroundStyle(DesignTokens.cardSecondaryText)
            if !game.resolvedVenueName.isEmpty {
                Text(game.resolvedVenueName)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            Text(game.startersLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.cardSecondaryText)
            if let attendance = game.attendanceLabel {
                Text(attendance)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
            if !game.eventTitle.isEmpty {
                Text(game.eventTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
            }
            if !game.friendsLabel.isEmpty {
                Text("w/ \(game.friendsLabel)")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.cardSecondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func gameLeaderCard(
        _ stat: GamePlayerStat,
        isPitcher: Bool,
        category: LeaderboardEngine.BatterCategory
    ) -> some View {
        gameLeaderCard(
            stat,
            isPitcher: isPitcher,
            valueLabel: category.display(for: stat),
            subtitle: "Top batter · \(category.title)"
        )
    }

    private func gameLeaderCard(
        _ stat: GamePlayerStat,
        isPitcher: Bool,
        category: LeaderboardEngine.PitcherCategory
    ) -> some View {
        gameLeaderCard(
            stat,
            isPitcher: isPitcher,
            valueLabel: category.display(for: stat),
            subtitle: "Top pitcher · \(category.title)"
        )
    }

    private func gameLeaderCard(
        _ stat: GamePlayerStat,
        isPitcher: Bool,
        valueLabel: String,
        subtitle: String
    ) -> some View {
        NavigationLink {
            PlayerDetailView(
                playerID: stat.playerID,
                playerName: stat.playerName,
                jerseyNumber: stat.jerseyNumber,
                teamID: stat.teamID,
                prefersPitching: isPitcher,
                league: game.resolvedLeague
            )
        } label: {
            JerseyCardView(
                number: stat.jerseyNumber,
                name: stat.playerName,
                subtitle: subtitle,
                valueLabel: valueLabel,
                theme: TeamTheme.forTeamID(stat.teamID),
                compact: true
            )
        }
        .buttonStyle(.plain)
    }

    private var diaryTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diary")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)
                Spacer()
                if isEditingDiary {
                    Button("Cancel") { cancelDiaryEdit() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText)
                    Button("Done") { saveDiaryEdit() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.accent)
                } else {
                    Button("Edit") { beginDiaryEdit() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.accent)
                }
            }

            if isEditingDiary {
                diaryEditor(title: "Event/Giveaway", text: $draftEventTitle)
                FriendEditorView(friendNames: $draftFriendNames)
                diaryEditor(title: "Notes", text: $draftNote)
                photoSection(editing: true)
            } else {
                diaryReadRow(title: "Event/Giveaway", value: game.eventTitle)
                diaryReadRow(title: "Friends", value: game.friendsLabel)
                diaryReadRow(title: "Notes", value: game.note)
                photoSection(editing: false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func diaryReadRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            Text(value.isEmpty ? "—" : value)
                .font(.body)
                .foregroundStyle(DesignTokens.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(DesignTokens.background.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func diaryEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText)
            TextField("", text: text, axis: .vertical)
                .padding(10)
                .background(DesignTokens.cardBackground)
                .foregroundStyle(DesignTokens.cardPrimaryText)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .lineLimit(2...5)
        }
    }

    private func photoSection(editing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText)
                Spacer()
                if editing {
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
            }

            if game.photos.isEmpty {
                Text(editing ? "No photos yet." : "—")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                InstagramPhotoGrid(
                    relativePaths: game.photos.map(\.relativePath),
                    onSelect: editing ? nil : { index in
                        enlargedPhotoPath = game.photos[index].relativePath
                    }
                ) { index in
                    if editing {
                        Button {
                            deletePhoto(game.photos[index])
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                                .padding(6)
                        }
                    } else {
                        EmptyView()
                    }
                }
            }
        }
    }

    private func beginDiaryEdit() {
        draftEventTitle = game.eventTitle
        draftFriendNames = game.friendNames
        draftNote = game.note
        isEditingDiary = true
    }

    private func cancelDiaryEdit() {
        isEditingDiary = false
        newPhotoItems = []
    }

    private func saveDiaryEdit() {
        game.eventTitle = draftEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        GameFriendStore.setFriends(names: draftFriendNames, on: game, modelContext: modelContext)
        game.note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        isEditingDiary = false
        CloudSyncTrigger.game(game, modelContext: modelContext)
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
        CloudSyncTrigger.game(game, modelContext: modelContext)
    }

    private func deletePhoto(_ photo: GamePhoto) {
        PhotoStore.delete(relativePath: photo.relativePath)
        game.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
        modelContext.delete(photo)
        try? modelContext.save()
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            base = game.playerStats.filter { $0.inningsPitchedOuts > 0 }
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
        NavigationLink {
            PlayerDetailView(
                playerID: stat.playerID,
                playerName: stat.playerName,
                jerseyNumber: stat.jerseyNumber,
                teamID: stat.teamID,
                prefersPitching: lineSegment == .pitchers || stat.isPitcher,
                league: game.resolvedLeague
            )
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(stat.jerseyNumber.isEmpty ? "#" : "#\(stat.jerseyNumber)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(DesignTokens.accent)
                    Text(stat.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.cardPrimaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
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
            .padding(12)
            .background(DesignTokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case diary
    case lines

    var id: String { rawValue }
    var title: String {
        switch self {
        case .diary: "Diary"
        case .lines: "Lines"
        }
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
        eventTitle: "Bobblehead Night",
        companions: "Sunbin",
        note: "Great game",
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
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self, GameFriend.self], inMemory: true)
}
