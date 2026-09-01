import SwiftUI
import SwiftData

/// Add/remove friends one at a time (text for now; linked accounts later).
struct FriendEditorView: View {
    @Binding var friendNames: [String]
    var appearance: FriendEditorAppearance = .gameDetailDiary
    @State private var newFriendName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Friends")
                .font(titleFont)
                .foregroundStyle(titleColor)

            if friendNames.isEmpty {
                Text("Add who you went with — one name at a time.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                ForEach(friendNames, id: \.self) { name in
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.body)
                            .foregroundStyle(fieldTextColor)
                        Spacer()
                        Button {
                            removeFriend(name)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(removeButtonColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(fieldPadding)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                TextField("Friend's name", text: $newFriendName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addFriend)
                    .padding(fieldPadding)
                    .background(fieldBackground)
                    .foregroundStyle(fieldTextColor)
                    .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))

                Button("Add", action: addFriend)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(fieldTextColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, fieldPadding)
                    .background(fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: fieldCornerRadius, style: .continuous))
                    .disabled(newFriendName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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

    private func addFriend() {
        let trimmed = newFriendName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !friendNames.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newFriendName = ""
            return
        }
        friendNames.append(trimmed)
        newFriendName = ""
    }

    private func removeFriend(_ name: String) {
        friendNames.removeAll { $0 == name }
    }
}

enum FriendEditorAppearance {
    case gameDetailDiary
    case addGameDiary
}

enum GameFriendStore {
    @MainActor
    static func setFriends(names: [String], on game: AttendedGame, modelContext: ModelContext) {
        let trimmed = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = trimmed.filter { seen.insert($0.lowercased()).inserted }

        for existing in game.friends {
            modelContext.delete(existing)
        }
        game.friends = unique.map { name in
            let friend = GameFriend(name: name)
            friend.game = game
            modelContext.insert(friend)
            return friend
        }
        game.syncCompanionsFromFriends()
    }

    @MainActor
    static func backfillFromLegacyCompanions(games: [AttendedGame], modelContext: ModelContext) {
        var changed = false
        for game in games where game.friends.isEmpty {
            let tokens = GameLogFilter.companionTokens(in: game.companions)
            guard !tokens.isEmpty else { continue }
            for name in tokens {
                let friend = GameFriend(name: name)
                friend.game = game
                modelContext.insert(friend)
                game.friends.append(friend)
            }
            game.syncCompanionsFromFriends()
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }
}
