import SwiftData
import SwiftUI

struct InviteFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let game: AttendedGame

    @State private var friends: [UserSearchResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var addingUserId: UUID?
    @State private var successMessage: String?

    private var availableFriends: [UserSearchResult] {
        friends.filter { !GameFriendStore.containsLinkedUser($0.userId, on: game) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && friends.isEmpty {
                    SpinningBaseballView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, friends.isEmpty {
                    ContentUnavailableView(
                        "Couldn't load friends",
                        systemImage: "person.2.slash",
                        description: Text(errorMessage)
                    )
                } else if friends.isEmpty {
                    ContentUnavailableView(
                        "No friends yet",
                        systemImage: "person.2",
                        description: Text("Become mutual friends with someone before adding them to a game.")
                    )
                } else if availableFriends.isEmpty {
                    ContentUnavailableView(
                        "Everyone's added",
                        systemImage: "checkmark.circle",
                        description: Text("All of your mutual friends are already on this game.")
                    )
                } else {
                    List(availableFriends) { friend in
                        Button {
                            Task { await addFriend(friend) }
                        } label: {
                            HStack {
                                UserSearchRow(result: friend)
                                Spacer(minLength: 8)
                                if addingUserId == friend.userId {
                                    SpinningBaseballView(fontSize: 18)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(addingUserId != nil)
                        .listRowBackground(DesignTokens.surface)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let successMessage {
                    Text(successMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.accent)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignTokens.surface)
                } else if let errorMessage, !friends.isEmpty {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(DesignTokens.surface)
                }
            }
            .task {
                await loadFriends()
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func loadFriends() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            friends = try await FollowService.shared.listMutualFollows()
        } catch {
            friends = []
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addFriend(_ friend: UserSearchResult) async {
        addingUserId = friend.userId
        successMessage = nil
        errorMessage = nil
        defer { addingUserId = nil }

        let previousLinked = Set(game.friends.compactMap(\.resolvedLinkedUserId))
        guard GameFriendStore.addLinkedFriend(friend, to: game, modelContext: modelContext) else {
            return
        }

        do {
            try modelContext.save()
            CloudSyncTrigger.game(game, modelContext: modelContext)
            try await GameInviteService.shared.sendInvitesForNewLinkedFriends(
                on: game,
                previousLinkedUserIds: previousLinked,
                modelContext: modelContext
            )
            let label = GameFriendStore.linkedDisplayName(for: friend)
            successMessage = "Added \(label) to this game."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
