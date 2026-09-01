import Foundation
import Supabase

enum SupabaseManager {
    private static var cached: SupabaseClient?

    static var client: SupabaseClient? {
        if let cached { return cached }
        guard let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey else { return nil }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        cached = client
        return client
    }
}
