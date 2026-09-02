import SwiftData
import SwiftUI
import UIKit

struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var onRequestsChanged: () -> Void = {}

    @State private var followRequests: [IncomingFollowRequest] = []
    @State private var gameInvites: [IncomingGameInvite] = []
    @State private var gameLeftUpdates: [GameLeftNotification] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actingFollowID: UUID?
    @State private var actingInviteID: UUID?
    @State private var avatarImages: [UUID: UIImage] = [:]

    private var isEmpty: Bool {
        followRequests.isEmpty && gameInvites.isEmpty && gameLeftUpdates.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, isEmpty {
                    ContentUnavailableView(
                        "Notifications unavailable",
                        systemImage: "bell.slash",
                        description: Text(errorMessage)
                    )
                } else if isEmpty {
                    ContentUnavailableView(
                        "All caught up",
                        systemImage: "bell",
                        description: Text("Follow requests and game invites will show up here.")
                    )
                } else {
                    List {
                        if !followRequests.isEmpty {
                            Section("Follow requests") {
                                ForEach(followRequests) { request in
                                    followRequestRow(request)
                                        .listRowBackground(DesignTokens.surface)
                                        .listRowInsets(rowInsets)
                                }
                            }
                        }

                        if !gameInvites.isEmpty {
                            Section("Game invites") {
                                ForEach(gameInvites) { invite in
                                    gameInviteRow(invite)
                                        .listRowBackground(DesignTokens.surface)
                                        .listRowInsets(rowInsets)
                                }
                            }
                        }

                        if !gameLeftUpdates.isEmpty {
                            Section("Game updates") {
                                ForEach(gameLeftUpdates) { update in
                                    gameLeftRow(update)
                                        .listRowBackground(DesignTokens.surface)
                                        .listRowInsets(rowInsets)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadNotifications()
            }
        }
        .background(DesignTokens.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8)
    }

    private func followRequestRow(_ request: IncomingFollowRequest) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RemoteProfileAvatarView(
                storagePath: request.avatarStoragePath,
                image: avatarBinding(for: request.requesterUserId),
                diameter: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(request.displayName.isEmpty ? request.usernameTag : request.displayName)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("wants to follow you")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            followRequestActions(for: request)
        }
        .padding(.vertical, 4)
        .task(id: request.avatarStoragePath) {
            await loadAvatar(for: request.requesterUserId, path: request.avatarStoragePath)
        }
    }

    private func gameInviteRow(_ invite: IncomingGameInvite) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RemoteProfileAvatarView(
                storagePath: invite.avatarStoragePath,
                image: avatarBinding(for: invite.fromUserId),
                diameter: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                (Text(invite.senderLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.primaryText)
                 + Text(" added you to a game they attended")
                    .foregroundStyle(DesignTokens.secondaryText))
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if !invite.gameDetailSubtitle.isEmpty {
                    Text(invite.gameDetailSubtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            inviteActions(for: invite)
        }
        .padding(.vertical, 4)
        .task(id: invite.avatarStoragePath) {
            await loadAvatar(for: invite.fromUserId, path: invite.avatarStoragePath)
        }
    }

    private func gameLeftRow(_ update: GameLeftNotification) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RemoteProfileAvatarView(
                storagePath: update.avatarStoragePath,
                image: avatarBinding(for: update.actorUserId),
                diameter: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                (Text(update.actorLabel)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignTokens.primaryText)
                 + Text(" left a game you logged")
                    .foregroundStyle(DesignTokens.secondaryText))
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                if !update.gameDetailSubtitle.isEmpty {
                    Text(update.gameDetailSubtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task(id: update.avatarStoragePath) {
            await loadAvatar(for: update.actorUserId, path: update.avatarStoragePath)
        }
    }

    @ViewBuilder
    private func followRequestActions(for request: IncomingFollowRequest) -> some View {
        let isDisabled = actingFollowID == request.id
        actionButtons(
            isDisabled: isDisabled,
            onAccept: { Task { await acceptFollow(request) } },
            onDecline: { Task { await declineFollow(request) } }
        )
    }

    @ViewBuilder
    private func inviteActions(for invite: IncomingGameInvite) -> some View {
        let isDisabled = actingInviteID == invite.id
        actionButtons(
            isDisabled: isDisabled,
            onAccept: { Task { await acceptInvite(invite) } },
            onDecline: { Task { await declineInvite(invite) } }
        )
    }

    @ViewBuilder
    private func actionButtons(
        isDisabled: Bool,
        onAccept: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                actionButton(title: "Accept", prominent: true, disabled: isDisabled, action: onAccept)
                actionButton(title: "Decline", prominent: false, disabled: isDisabled, action: onDecline)
            }

            VStack(alignment: .trailing, spacing: 6) {
                actionButton(title: "Accept", prominent: true, disabled: isDisabled, action: onAccept)
                actionButton(title: "Decline", prominent: false, disabled: isDisabled, action: onDecline)
            }
        }
        .frame(alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func actionButton(
        title: String,
        prominent: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.white : DesignTokens.primaryText)
        .background(prominent ? DesignTokens.accent : DesignTokens.surface)
        .clipShape(Capsule())
        .overlay {
            if !prominent {
                Capsule()
                    .strokeBorder(DesignTokens.secondaryText.opacity(0.35), lineWidth: 1)
            }
        }
        .disabled(disabled)
    }

    private func avatarBinding(for userId: UUID) -> Binding<UIImage?> {
        Binding(
            get: { avatarImages[userId] },
            set: { avatarImages[userId] = $0 }
        )
    }

    private func loadAvatar(for userId: UUID, path: String?) async {
        let image = await SocialProfileService.shared.downloadAvatar(path: path)
        if let image {
            avatarImages[userId] = image
        }
    }

    @MainActor
    private func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let follows = FollowService.shared.incomingRequests()
            async let invites = GameInviteService.shared.incomingInvites()
            async let leftUpdates = GameInviteService.shared.gameLeftNotifications()
            followRequests = try await follows
            gameInvites = try await invites
            gameLeftUpdates = try await leftUpdates
            if !gameLeftUpdates.isEmpty {
                try? await GameInviteService.shared.markGameLeftNotificationsRead()
                onRequestsChanged()
            }
        } catch {
            followRequests = []
            gameInvites = []
            gameLeftUpdates = []
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func acceptFollow(_ request: IncomingFollowRequest) async {
        actingFollowID = request.id
        defer { actingFollowID = nil }

        do {
            try await FollowService.shared.acceptFollow(from: request.requesterUserId)
            followRequests.removeAll { $0.id == request.id }
            onRequestsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func declineFollow(_ request: IncomingFollowRequest) async {
        actingFollowID = request.id
        defer { actingFollowID = nil }

        do {
            try await FollowService.shared.declineFollow(from: request.requesterUserId)
            followRequests.removeAll { $0.id == request.id }
            onRequestsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func acceptInvite(_ invite: IncomingGameInvite) async {
        actingInviteID = invite.id
        defer { actingInviteID = nil }

        do {
            try await GameInviteService.shared.acceptInvite(invite.id, modelContext: modelContext)
            gameInvites.removeAll { $0.id == invite.id }
            onRequestsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func declineInvite(_ invite: IncomingGameInvite) async {
        actingInviteID = invite.id
        defer { actingInviteID = nil }

        do {
            try await GameInviteService.shared.declineInvite(invite.id)
            gameInvites.removeAll { $0.id == invite.id }
            onRequestsChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
