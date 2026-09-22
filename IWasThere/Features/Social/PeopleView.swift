import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.openGamesTogether) private var openGamesTogether
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var allGames: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var searchText = ""
    @State private var debouncedQuery = ""
    @State private var friends: [UserSearchResult] = []
    @State private var searchResults: [UserSearchResult] = []
    @State private var isLoadingFriends = true
    @State private var isSearching = false
    @State private var friendsError: String?
    @State private var searchError: String?
    @State private var friendsRefreshToken = UUID()
    @State private var friendRankMode: FriendListRankMode = .gamesTogether

    private var isActivelySearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var rankedPeople: [PeopleRankItem] {
        let profile = profiles.first
        return GameLogFilter.rankPeople(
            mutualFriends: friends,
            games: allGames,
            mlbFavoriteTeamID: profile?.favoriteTeamID,
            kboFavoriteTeamID: profile?.favoriteKBOTeamID,
            mode: friendRankMode
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isActivelySearching {
                    searchContent
                } else {
                    friendsContent
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search @username or name")
            .onChange(of: searchText) { _, newValue in
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard searchText == newValue else { return }
                    debouncedQuery = newValue
                }
            }
            .task {
                await loadFriends()
            }
            .refreshable {
                await loadFriends()
            }
            .task(id: debouncedQuery) {
                await runSearch()
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var friendsContent: some View {
        if isLoadingFriends && friends.isEmpty && rankedPeople.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let friendsError, friends.isEmpty && rankedPeople.isEmpty {
            ContentUnavailableView(
                "Friends unavailable",
                systemImage: "person.2.slash",
                description: Text(friendsError)
            )
        } else if rankedPeople.isEmpty {
            ContentUnavailableView(
                "No friends yet",
                systemImage: "person.2",
                description: Text("Search for people and follow each other, or tag companions when you add a game.")
            )
        } else {
            List {
                Section {
                    let ranks = GameLogFilter.competitionRanks(for: rankedPeople, mode: friendRankMode)
                    ForEach(Array(rankedPeople.enumerated()), id: \.element.id) { index, item in
                        peopleRow(item, badge: FriendRankBadge.forCompetitionRank(ranks[index]))
                    }
                } header: {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Friends")
                            .foregroundStyle(DesignTokens.secondaryText)
                        Spacer(minLength: 8)
                        friendRankModeMenu
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func peopleRow(_ item: PeopleRankItem, badge: FriendRankBadge?) -> some View {
        switch item {
        case .account(let rankedFriend):
            NavigationLink {
                UserProfileView(userId: rankedFriend.friend.userId)
            } label: {
                UserSearchRow(
                    result: rankedFriend.friend,
                    gamesTogether: rankedFriend.gamesTogether,
                    togetherAttendance: rankedFriend.togetherAttendance,
                    rankMode: friendRankMode,
                    rankBadge: badge,
                    avatarRefreshToken: friendsRefreshToken
                )
            }
            .listRowBackground(DesignTokens.surface)
            .contextMenu {
                if rankedFriend.gamesTogether > 0 {
                    Button {
                        openGamesTogether?(GameFriendFilterOption(friend: rankedFriend.friend))
                    } label: {
                        Label("View games together", systemImage: "baseball")
                    }
                }
            }

        case .localCompanion(let companion):
            NavigationLink {
                LocalCompanionDetailView(companionName: companion.name)
            } label: {
                LocalCompanionRow(
                    name: companion.name,
                    gamesTogether: companion.gamesTogether,
                    togetherAttendance: companion.togetherAttendance,
                    rankMode: friendRankMode,
                    rankBadge: badge
                )
            }
            .listRowBackground(DesignTokens.surface)
            .contextMenu {
                if companion.gamesTogether > 0 {
                    Button {
                        openGamesTogether?(
                            GameFriendFilterOption(
                                id: "name:\(companion.name.lowercased())",
                                chipLabel: companion.name,
                                linkedUserId: nil,
                                matchName: companion.name
                            )
                        )
                    } label: {
                        Label("View games together", systemImage: "baseball")
                    }
                }
            }
        }
    }

    private var friendRankModeMenu: some View {
        Menu {
            ForEach(FriendListRankMode.allCases) { mode in
                Button {
                    friendRankMode = mode
                } label: {
                    if mode == friendRankMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: friendRankMode.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(DesignTokens.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignTokens.surface)
            .clipShape(Capsule())
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var searchContent: some View {
        if isSearching && searchResults.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let searchError, searchResults.isEmpty {
            ContentUnavailableView(
                "Search unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text(searchError)
            )
        } else if searchResults.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Try a different @username or name.")
            )
        } else {
            List(searchResults) { result in
                NavigationLink {
                    UserProfileView(userId: result.userId)
                } label: {
                    UserSearchRow(result: result, avatarRefreshToken: friendsRefreshToken)
                }
                .listRowBackground(DesignTokens.surface)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @MainActor
    private func loadFriends() async {
        isLoadingFriends = true
        friendsError = nil
        defer { isLoadingFriends = false }

        do {
            friends = try await FollowService.shared.listMutualFollows()
            friendsRefreshToken = UUID()
        } catch {
            friends = []
            friendsError = error.localizedDescription
        }
    }

    @MainActor
    private func runSearch() async {
        let trimmed = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            searchResults = try await SocialProfileService.shared.searchUsers(query: trimmed)
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
    }
}

struct FriendRankBadgeView: View {
    let badge: FriendRankBadge

    var body: some View {
        switch badge {
        case .medal(let medal):
            Image(systemName: medal.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(
                    Color(
                        red: medal.color.red,
                        green: medal.color.green,
                        blue: medal.color.blue
                    )
                )
                .frame(width: 24)
        case .number(let rank):
            Text("\(rank)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DesignTokens.secondaryText)
                .monospacedDigit()
                .frame(width: 24)
        }
    }
}

struct LocalCompanionRow: View {
    let name: String
    var gamesTogether: Int?
    var togetherAttendance: LeaderboardEngine.AttendanceRecord?
    var rankMode: FriendListRankMode?
    var rankBadge: FriendRankBadge?

    var body: some View {
        HStack(spacing: 12) {
            if let rankBadge {
                FriendRankBadgeView(badge: rankBadge)
            }

            ProfileAvatarView(image: nil, diameter: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)
                Text("No account linked")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
            }

            Spacer(minLength: 8)

            if let trailingLabel = trailingLabel {
                Text(trailingLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private var trailingLabel: String? {
        guard let gamesTogether else { return nil }
        switch rankMode {
        case .winRate:
            guard let togetherAttendance, togetherAttendance.games > 0 else { return "—" }
            return togetherAttendance.winPercentageLabel
        case .gamesTogether, nil:
            return gamesTogether == 1 ? "1 game" : "\(gamesTogether) games"
        }
    }
}

struct UserSearchRow: View {
    let result: UserSearchResult
    var gamesTogether: Int?
    var togetherAttendance: LeaderboardEngine.AttendanceRecord?
    var rankMode: FriendListRankMode?
    var rankBadge: FriendRankBadge?
    var avatarRefreshToken: UUID = UUID()
    @State private var avatarImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if let rankBadge {
                FriendRankBadgeView(badge: rankBadge)
            }

            RemoteProfileAvatarView(storagePath: result.avatarStoragePath, image: $avatarImage, diameter: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayName.isEmpty ? result.usernameTag : result.displayName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)
                if !result.displayName.isEmpty {
                    Text(result.usernameTag)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)
                }
                if result.visibility == .private {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Private")
                            .font(.caption)
                    }
                    .foregroundStyle(DesignTokens.secondaryText)
                }
            }

            Spacer(minLength: 8)

            if let trailingLabel = friendsListTrailingLabel {
                Text(trailingLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .task(id: avatarRefreshToken) {
            avatarImage = await SocialProfileService.shared.downloadAvatar(
                path: result.avatarStoragePath,
                forceRefresh: true
            )
        }
    }

    private var friendsListTrailingLabel: String? {
        guard let gamesTogether else { return nil }
        switch rankMode {
        case .winRate:
            guard let togetherAttendance, togetherAttendance.games > 0 else { return "—" }
            return togetherAttendance.winPercentageLabel
        case .gamesTogether, nil:
            return gamesTogetherLabel(gamesTogether)
        }
    }

    private func gamesTogetherLabel(_ count: Int) -> String {
        count == 1 ? "1 game" : "\(count) games"
    }
}

#Preview {
    PeopleView()
}
