import Foundation
import Supabase
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AuthSession {
    static let shared = AuthSession()

    private(set) var isAuthenticated = false
    private(set) var userId: UUID?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var infoMessage: String?
    /// True only right after sign-up (or email confirmation), until profile setup finishes.
    private(set) var shouldShowProfileOnboarding = false

    /// In-memory only — used to sign in after email confirmation when the deep link is unavailable.
    private var pendingSignUpPassword: String?

    private var didStartAuthListener = false

    private init() {}

    var isAwaitingEmailConfirmation: Bool {
        ProfileOnboardingStore.isAwaitingEmailConfirmation()
    }

    var pendingSignUpEmail: String? {
        ProfileOnboardingStore.pendingSignUpEmail()
    }

    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }

        guard SupabaseConfig.isConfigured, SupabaseManager.client != nil else {
            errorMessage = "Add SupabaseConfig.plist — see docs/BACKEND.md"
            isAuthenticated = false
            userId = nil
            return
        }

        startAuthStateListenerIfNeeded()

        if ProfileOnboardingStore.isAwaitingEmailConfirmation() {
            try? await requireClient().auth.signOut()
            isAuthenticated = false
            userId = nil
            errorMessage = nil
            return
        }

        do {
            let session = try await requireClient().auth.session
            userId = session.user.id
            isAuthenticated = true
            errorMessage = nil
        } catch {
            isAuthenticated = false
            userId = nil
            errorMessage = nil
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        clearPendingSignUp()
        shouldShowProfileOnboarding = false

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }

        do {
            try await requireClient().auth.signIn(email: trimmedEmail, password: password)
            let session = try await requireClient().auth.session
            userId = session.user.id
            isAuthenticated = true
        } catch {
            errorMessage = friendlyAuthError(error)
        }
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        do {
            // Drop any existing session so a new account cannot inherit the previous user's data.
            try? await requireClient().auth.signOut()
            isAuthenticated = false
            userId = nil
            shouldShowProfileOnboarding = false

            let response = try await requireClient().auth.signUp(
                email: trimmedEmail,
                password: password,
                redirectTo: AuthConfig.emailRedirectURL
            )
            if let session = response.session {
                userId = session.user.id
                isAuthenticated = true
                shouldShowProfileOnboarding = true
            } else {
                pendingSignUpPassword = password
                ProfileOnboardingStore.markAwaitingEmailConfirmation(email: trimmedEmail)
                isAuthenticated = false
                userId = nil
            }
        } catch {
            errorMessage = friendlyAuthError(error)
        }
    }

    func checkEmailConfirmation() async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        guard ProfileOnboardingStore.isAwaitingEmailConfirmation() else { return }

        let pendingEmail = ProfileOnboardingStore.pendingSignUpEmail()?.lowercased()

        if let session = try? await requireClient().auth.session,
           sessionMatchesPendingEmail(session, pendingEmail: pendingEmail) {
            await completeEmailConfirmation(session: session)
            return
        }

        do {
            try await requireClient().auth.refreshSession()
            let session = try await requireClient().auth.session
            if sessionMatchesPendingEmail(session, pendingEmail: pendingEmail) {
                await completeEmailConfirmation(session: session)
                return
            }
        } catch {
            // Fall through to password sign-in attempt.
        }

        guard let email = pendingEmail, let password = pendingSignUpPassword else {
            errorMessage = "Email not confirmed yet. Open the link in your inbox first."
            return
        }

        do {
            try await requireClient().auth.signIn(email: email, password: password)
            let session = try await requireClient().auth.session
            await completeEmailConfirmation(session: session)
        } catch {
            errorMessage = "Email not confirmed yet. Open the link in your inbox, then try again."
        }
    }

    func cancelPendingSignUp() {
        clearPendingSignUp()
        Task {
            try? await SupabaseManager.client?.auth.signOut()
            isAuthenticated = false
            userId = nil
        }
    }

    func handleIncomingURL(_ url: URL) async {
        guard SupabaseConfig.isConfigured else { return }

        do {
            try await requireClient().auth.session(from: url)
            let session = try await requireClient().auth.session

            if ProfileOnboardingStore.isAwaitingEmailConfirmation() {
                let pendingEmail = ProfileOnboardingStore.pendingSignUpEmail()?.lowercased()
                guard sessionMatchesPendingEmail(session, pendingEmail: pendingEmail) else {
                    errorMessage = "That confirmation link does not match the account you are creating."
                    return
                }
                await completeEmailConfirmation(session: session)
            } else {
                userId = session.user.id
                isAuthenticated = true
            }
        } catch {
            errorMessage = friendlyAuthError(error)
        }
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    func clearProfileOnboarding() {
        shouldShowProfileOnboarding = false
    }

    func signOut(modelContext: ModelContext? = nil) async {
        try? await SupabaseManager.client?.auth.signOut()
        if let modelContext {
            LocalUserDataStore.clearUserData(modelContext: modelContext)
        }
        LocalUserDataStore.clearSyncedUserId()
        isAuthenticated = false
        userId = nil
        infoMessage = nil
        shouldShowProfileOnboarding = false
        clearPendingSignUp()
    }

    func deleteAccount(modelContext: ModelContext) async throws {
        let client = try requireClient()
        guard userId != nil else {
            throw AuthError.notAuthenticated
        }

        try await client.rpc("delete_own_account").execute()
        LocalUserDataStore.clearUserData(modelContext: modelContext)
        LocalUserDataStore.clearSyncedUserId()
        try await client.auth.signOut()
        isAuthenticated = false
        self.userId = nil
        shouldShowProfileOnboarding = false
        infoMessage = nil
        errorMessage = nil
        clearPendingSignUp()
    }

    private func startAuthStateListenerIfNeeded() {
        guard !didStartAuthListener, let client = SupabaseManager.client else { return }
        didStartAuthListener = true

        Task {
            for await (event, session) in client.auth.authStateChanges {
                if ProfileOnboardingStore.isAwaitingEmailConfirmation() {
                    guard event == .signedIn, let session else { continue }
                    let pendingEmail = ProfileOnboardingStore.pendingSignUpEmail()?.lowercased()
                    guard sessionMatchesPendingEmail(session, pendingEmail: pendingEmail) else { continue }
                    await completeEmailConfirmation(session: session)
                    continue
                }

                guard [.signedIn, .initialSession].contains(event), let session else { continue }
                userId = session.user.id
                isAuthenticated = true
            }
        }
    }

    private func completeEmailConfirmation(session: Session) async {
        userId = session.user.id
        isAuthenticated = true
        shouldShowProfileOnboarding = true
        clearPendingSignUp()
    }

    private func clearPendingSignUp() {
        pendingSignUpPassword = nil
        ProfileOnboardingStore.clearAwaitingEmailConfirmation()
    }

    private func sessionMatchesPendingEmail(_ session: Session, pendingEmail: String?) -> Bool {
        guard let pendingEmail else { return false }
        return session.user.email?.lowercased() == pendingEmail
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseManager.client else {
            throw AuthError.notConfigured
        }
        return client
    }

    private func friendlyAuthError(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("invalid login") {
            return "Wrong email or password."
        }
        if text.localizedCaseInsensitiveContains("already registered") {
            return "That email is already registered. Try signing in."
        }
        return text
    }

    enum AuthError: LocalizedError {
        case notConfigured
        case notAuthenticated

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase is not configured."
            case .notAuthenticated: "You are not signed in."
            }
        }
    }
}
