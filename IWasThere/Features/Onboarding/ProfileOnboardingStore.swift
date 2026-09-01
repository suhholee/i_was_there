import Foundation

enum ProfileOnboardingStore {
    private static let awaitingEmailKey = "profileOnboardingAwaitingEmailConfirmation"
    private static let pendingEmailKey = "profileOnboardingPendingSignUpEmail"

    static func markAwaitingEmailConfirmation(email: String) {
        UserDefaults.standard.set(true, forKey: awaitingEmailKey)
        UserDefaults.standard.set(email, forKey: pendingEmailKey)
    }

    static func isAwaitingEmailConfirmation() -> Bool {
        UserDefaults.standard.bool(forKey: awaitingEmailKey)
    }

    static func pendingSignUpEmail() -> String? {
        UserDefaults.standard.string(forKey: pendingEmailKey)
    }

    static func clearAwaitingEmailConfirmation() {
        UserDefaults.standard.removeObject(forKey: awaitingEmailKey)
        UserDefaults.standard.removeObject(forKey: pendingEmailKey)
    }
}
