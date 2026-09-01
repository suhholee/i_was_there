import Foundation

enum AuthConfig {
    /// Add this URL under Supabase → Authentication → URL Configuration → Redirect URLs.
    static let emailRedirectURL = URL(string: "com.suhholee.iwasthere://auth-callback")!
}
