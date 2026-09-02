import Foundation

enum UsernameRules {
    static let minLength = 3
    static let maxLength = 30

    private static let reserved: Set<String> = [
        "admin", "help", "iwasthere", "moderator", "root", "support", "system"
    ]

    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        return value
    }

    static func isValidFormat(_ raw: String) -> Bool {
        let value = normalize(raw)
        guard value.count >= minLength, value.count <= maxLength else { return false }
        guard !reserved.contains(value) else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.lowercaseLetters.contains($0)
                || CharacterSet.decimalDigits.contains($0)
                || $0 == "_"
        }
    }

    static func validationMessage(for raw: String) -> String? {
        let value = normalize(raw)
        if value.isEmpty {
            return "Choose a username."
        }
        if value.count < minLength {
            return "Usernames need at least \(minLength) characters."
        }
        if value.count > maxLength {
            return "Usernames can be at most \(maxLength) characters."
        }
        if reserved.contains(value) {
            return "That username is reserved."
        }
        if !isValidFormat(raw) {
            return "Use letters, numbers, and underscores only."
        }
        return nil
    }
}
