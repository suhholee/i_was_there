import SwiftUI
import SwiftData

struct DiaryFriendEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var linkedUserId: UUID?

    init(id: UUID = UUID(), name: String, linkedUserId: UUID? = nil) {
        self.id = id
        self.name = name
        self.linkedUserId = linkedUserId
    }
}

/// Add diary friends by name or mutual-friend @tag.
struct FriendEditorView: View {
    @Binding var friends: [DiaryFriendEntry]
    var appearance: FriendEditorAppearance = .gameDetailDiary
    var canRemoveFriends: Bool = true

    @State private var newFriendName = ""
    @State private var mutualFriends: [UserSearchResult] = []
    @State private var isLoadingMutualFriends = false

    private var trimmedInput: String {
        newFriendName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var tagQuery: String? {
        guard trimmedInput.hasPrefix("@") else { return nil }
        let query = String(trimmedInput.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? nil : query
    }

    private var tagSuggestions: [UserSearchResult] {
        guard let tagQuery, tagQuery.count >= 1 else { return [] }
        let linkedIDs = Set(friends.compactMap(\.linkedUserId))
        return mutualFriends.filter { friend in
            guard !linkedIDs.contains(friend.userId) else { return false }
            return friend.username.localizedCaseInsensitiveContains(tagQuery)
                || friend.displayName.localizedCaseInsensitiveContains(tagQuery)
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Friends")
                .font(titleFont)
                .foregroundStyle(titleColor)

            if friends.isEmpty {
                Text(canRemoveFriends
                    ? "Add who you went with — type a name or search mutual friends with @."
                    : "Add who else you went with — you can't remove friends already on this game.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                ForEach(friends) { friend in
                    HStack(spacing: 8) {
                        Text(friend.name)
                            .font(.body)
                            .foregroundStyle(fieldTextColor)
                        Spacer(minLength: 8)
                        if canRemoveFriends {
                            Button {
                                removeFriend(friend)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(removeButtonColor)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(fieldPadding)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Name or @username", text: $newFriendName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addPlainFriend)
                        .padding(fieldPadding)
                        .background(fieldBackground)
                        .foregroundStyle(fieldTextColor)
                        .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))

                    Button("Add", action: addPlainFriend)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(fieldTextColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, fieldPadding)
                        .background(fieldBackground)
                        .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                        .disabled(trimmedInput.isEmpty || tagQuery != nil)
                }

                if tagQuery != nil {
                    if isLoadingMutualFriends {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else if tagSuggestions.isEmpty, let tagQuery, tagQuery.count >= 2 {
                        Text("No mutual friends match @\(tagQuery).")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText)
                    } else {
                        ForEach(tagSuggestions) { friend in
                            Button {
                                addLinkedFriend(friend)
                            } label: {
                                UserSearchRow(result: friend)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(fieldBackground.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                        }
                    }
                }
            }
        }
        .task {
            await loadMutualFriends()
        }
    }

    private var titleFont: Font {
        appearance == .gameDetailDiary
            ? .caption.weight(.semibold)
            : .subheadline.weight(.semibold)
    }

    private var titleColor: Color {
        appearance == .gameDetailDiary
            ? DesignTokens.secondaryText
            : DesignTokens.primaryText
    }

    private var fieldBackground: Color {
        appearance == .gameDetailDiary
            ? DesignTokens.cardBackground
            : DesignTokens.surface
    }

    private var fieldTextColor: Color {
        appearance == .gameDetailDiary
            ? DesignTokens.cardPrimaryText
            : DesignTokens.primaryText
    }

    private var removeButtonColor: Color {
        appearance == .gameDetailDiary
            ? DesignTokens.cardSecondaryText
            : DesignTokens.secondaryText
    }

    private var fieldPadding: CGFloat {
        appearance == .gameDetailDiary ? 10 : 12
    }

    private var fieldCornerRadius: CGFloat {
        appearance == .gameDetailDiary ? 8 : 10
    }

    @MainActor
    private func loadMutualFriends() async {
        guard AuthSession.shared.isAuthenticated else {
            mutualFriends = []
            return
        }
        isLoadingMutualFriends = true
        defer { isLoadingMutualFriends = false }
        mutualFriends = (try? await FollowService.shared.listMutualFollows()) ?? []
    }

    private func addPlainFriend() {
        guard tagQuery == nil else { return }
        let trimmed = trimmedInput
        guard !trimmed.isEmpty else { return }
        guard !containsFriend(named: trimmed, linkedUserId: nil) else {
            newFriendName = ""
            return
        }
        friends.append(DiaryFriendEntry(name: trimmed))
        newFriendName = ""
    }

    private func addLinkedFriend(_ friend: UserSearchResult) {
        let label = GameFriendStore.linkedDisplayName(for: friend)
        guard !containsFriend(named: label, linkedUserId: friend.userId) else {
            newFriendName = ""
            return
        }
        friends.append(DiaryFriendEntry(name: label, linkedUserId: friend.userId))
        newFriendName = ""
    }

    private func removeFriend(_ friend: DiaryFriendEntry) {
        withAnimation(.easeOut(duration: 0.15)) {
            friends = friends.filter { $0.id != friend.id }
        }
    }

    private func containsFriend(named name: String, linkedUserId: UUID?) -> Bool {
        if let linkedUserId {
            return friends.contains { $0.linkedUserId == linkedUserId }
        }
        return friends.contains {
            $0.linkedUserId == nil
                && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }
}

enum FriendEditorAppearance {
    case gameDetailDiary
    case addGameDiary
}

enum GameFriendStore {
    static func linkedDisplayName(for friend: UserSearchResult) -> String {
        let display = friend.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let username = friend.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        return "Friend"
    }

    static func containsLinkedUser(_ userId: UUID, on game: AttendedGame) -> Bool {
        game.friends.contains { $0.resolvedLinkedUserId == userId }
    }

    @MainActor
    @discardableResult
    static func addLinkedFriend(
        _ friend: UserSearchResult,
        to game: AttendedGame,
        modelContext: ModelContext
    ) -> Bool {
        guard !containsLinkedUser(friend.userId, on: game) else { return false }
        var entries = entries(from: game)
        entries.append(
            DiaryFriendEntry(
                name: linkedDisplayName(for: friend),
                linkedUserId: friend.userId
            )
        )
        setFriends(entries: entries, on: game, modelContext: modelContext)
        return true
    }

    static func entries(from game: AttendedGame) -> [DiaryFriendEntry] {
        game.friends.map { friend in
            DiaryFriendEntry(
                id: stableEntryID(for: friend),
                name: friend.name,
                linkedUserId: friend.resolvedLinkedUserId
            )
        }
    }

    private static func stableEntryID(for friend: GameFriend) -> UUID {
        if let linked = friend.resolvedLinkedUserId {
            return linked
        }
        return UUID()
    }

    static func containsEntry(_ entry: DiaryFriendEntry, in list: [DiaryFriendEntry]) -> Bool {
        if let linkedUserId = entry.linkedUserId {
            return list.contains { $0.linkedUserId == linkedUserId }
        }
        return list.contains {
            $0.linkedUserId == nil
                && $0.name.localizedCaseInsensitiveCompare(entry.name) == .orderedSame
        }
    }

    /// Keeps every baseline friend and appends new additions from the draft.
    static func entriesAllowingAdditionsOnly(
        baseline: [DiaryFriendEntry],
        draft: [DiaryFriendEntry]
    ) -> [DiaryFriendEntry] {
        var result = baseline
        for entry in draft where !containsEntry(entry, in: result) {
            result.append(entry)
        }
        return result
    }

    private static func normalizedEntries(_ entries: [DiaryFriendEntry]) -> [DiaryFriendEntry] {
        entries
            .map {
                DiaryFriendEntry(
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    linkedUserId: $0.linkedUserId
                )
            }
            .filter { !$0.name.isEmpty }
            .sorted {
                if $0.linkedUserId != $1.linkedUserId {
                    return ($0.linkedUserId?.uuidString ?? "") < ($1.linkedUserId?.uuidString ?? "")
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func entriesAreEquivalent(_ lhs: [DiaryFriendEntry], _ rhs: [DiaryFriendEntry]) -> Bool {
        let left = normalizedEntries(lhs)
        let right = normalizedEntries(rhs)
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { $0.name == $1.name && $0.linkedUserId == $1.linkedUserId }
    }

    @MainActor
    @discardableResult
    static func normalizeSharedCopyFriendsIfNeeded(
        on game: AttendedGame,
        modelContext: ModelContext
    ) async -> Bool {
        guard game.isSharedGameCopy,
              let ownerId = UUID(uuidString: game.invitedFromUserId),
              let currentUserId = AuthSession.shared.userId else {
            return false
        }

        var revisedEntries = Self.entries(from: game).filter { $0.linkedUserId != currentUserId }

        if !revisedEntries.contains(where: { $0.linkedUserId == ownerId }) {
            let ownerName: String
            if let profile = try? await SocialProfileService.shared.fetchProfile(userId: ownerId) {
                let display = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
                ownerName = !display.isEmpty ? display : (!username.isEmpty ? username : "Friend")
            } else {
                ownerName = "Friend"
            }
            revisedEntries.insert(DiaryFriendEntry(name: ownerName, linkedUserId: ownerId), at: 0)
        }

        guard !entriesAreEquivalent(Self.entries(from: game), revisedEntries) else { return false }

        setFriends(entries: revisedEntries, on: game, modelContext: modelContext)
        return true
    }

    @MainActor
    static func setFriends(entries: [DiaryFriendEntry], on game: AttendedGame, modelContext: ModelContext) {
        var seenNames = Set<String>()
        var seenLinked = Set<UUID>()
        let unique = entries.compactMap { entry -> DiaryFriendEntry? in
            let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let linkedUserId = entry.linkedUserId {
                guard seenLinked.insert(linkedUserId).inserted else { return nil }
            } else {
                let key = trimmed.lowercased()
                guard seenNames.insert(key).inserted else { return nil }
            }
            return DiaryFriendEntry(name: trimmed, linkedUserId: entry.linkedUserId)
        }

        for existing in game.friends {
            modelContext.delete(existing)
        }
        game.friends = unique.map { entry in
            let friend = GameFriend(name: entry.name, linkedUserId: entry.linkedUserId)
            friend.game = game
            modelContext.insert(friend)
            return friend
        }
        game.syncCompanionsFromFriends()
    }

    @MainActor
    static func setFriends(names: [String], on game: AttendedGame, modelContext: ModelContext) {
        let entries = names.map { DiaryFriendEntry(name: $0) }
        setFriends(entries: entries, on: game, modelContext: modelContext)
    }

    @MainActor
    static func backfillFromLegacyCompanions(games: [AttendedGame], modelContext: ModelContext) {
        var changed = false
        for game in games where game.friends.isEmpty {
            let tokens = GameLogFilter.companionTokens(in: game.companions)
            guard !tokens.isEmpty else { continue }
            setFriends(names: tokens, on: game, modelContext: modelContext)
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }
}
