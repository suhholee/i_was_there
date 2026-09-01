import Foundation

enum SupabaseConfig {
    static var url: URL? {
        guard let raw = string(for: "SUPABASE_URL"),
              let url = URL(string: raw),
              !raw.contains("YOUR_PROJECT")
        else {
            return nil
        }
        return url
    }

    static var anonKey: String? {
        guard let key = string(for: "SUPABASE_ANON_KEY"),
              !key.contains("YOUR_ANON")
        else {
            return nil
        }
        return key
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }

    private static func string(for key: String) -> String? {
        for name in ["SupabaseConfig", "SupabaseConfig.example"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let value = dict[key] as? String,
                  !value.isEmpty
            else { continue }
            return value
        }
        return nil
    }
}
