import SwiftUI
import SwiftData

private enum PostAuthPhase {
    case loading
    case onboarding
    case main
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var auth = AuthSession.shared
    @State private var postAuthPhase: PostAuthPhase = .loading
    @State private var syncedUserId: UUID?

    var body: some View {
        Group {
            if auth.isAwaitingEmailConfirmation {
                EmailConfirmationPendingView(auth: auth)
            } else if auth.isLoading {
                LaunchLoadingView()
            } else if auth.isAuthenticated, let userId = auth.userId {
                switch postAuthPhase {
                case .loading:
                    LaunchLoadingView()
                case .onboarding:
                    ProfileOnboardingView(userId: userId) {
                        auth.clearProfileOnboarding()
                        postAuthPhase = .main
                    }
                case .main:
                    RootTabView()
                }
            } else {
                SignInView(auth: auth)
            }
        }
        .task {
            await auth.bootstrap()
        }
        .onChange(of: auth.userId) { oldUserId, newUserId in
            if newUserId == nil, oldUserId != nil {
                LocalUserDataStore.clearUserData(modelContext: modelContext)
                LocalUserDataStore.clearSyncedUserId()
                syncedUserId = nil
                postAuthPhase = .loading
            }
        }
        .task(id: auth.userId) {
            guard auth.isAuthenticated, let userId = auth.userId else {
                postAuthPhase = .loading
                return
            }

            if syncedUserId != userId {
                syncedUserId = userId
                postAuthPhase = .loading
                await CloudSyncService.shared.performFullSync(
                    modelContext: modelContext,
                    userId: userId
                )
                postAuthPhase = auth.shouldShowProfileOnboarding ? .onboarding : .main
            }
        }
        .onChange(of: auth.shouldShowProfileOnboarding) { _, shouldShow in
            guard auth.isAuthenticated, shouldShow else { return }
            postAuthPhase = .onboarding
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            StadiumAuthBackground()
            VStack(spacing: 16) {
                Image(systemName: "baseball.fill")
                    .font(.title)
                    .foregroundStyle(DesignTokens.accent)
                ProgressView()
                    .tint(.white)
            }
        }
        .preferredColorScheme(.dark)
    }
}
