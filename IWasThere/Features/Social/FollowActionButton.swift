import SwiftUI
import UIKit

struct FollowActionButton: View {
    let status: FollowRelationshipStatus
    var isLoading: Bool = false
    var onFollow: () -> Void = {}
    var onCancelRequest: () -> Void = {}
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}
    var onUnfollow: () -> Void = {}

    var body: some View {
        switch status {
        case .selfProfile:
            EmptyView()
        case .none:
            primaryButton(title: "Follow", action: onFollow)
        case .outgoingPending:
            secondaryButton(title: "Requested", action: onCancelRequest)
        case .incomingPending:
            HStack(spacing: 10) {
                primaryButton(title: "Accept", action: onAccept)
                secondaryButton(title: "Decline", action: onDecline)
            }
        case .mutual:
            secondaryButton(title: "Friends", action: onUnfollow)
        }
    }

    @ViewBuilder
    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(DesignTokens.accent)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(DesignTokens.surface)
            .foregroundStyle(DesignTokens.primaryText)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(DesignTokens.secondaryText.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
