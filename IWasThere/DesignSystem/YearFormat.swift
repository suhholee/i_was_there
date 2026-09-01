import SwiftUI

/// Years must never use locale grouping (`2,016` → `2016`).
/// Prefer `text(_:)` / `verbatim(_:)` in SwiftUI — `Text("… \(year) …")` formats `Int` with commas.
enum YearFormat {
    static func string(_ year: Int) -> String {
        String(year)
    }

    /// Safe for SwiftUI labels (avoids LocalizedStringKey number grouping).
    static func text(_ year: Int) -> Text {
        Text(verbatim: string(year))
    }

    static func verbatim(_ template: String, year: Int) -> Text {
        Text(verbatim: template.replacingOccurrences(of: "%@", with: string(year)))
    }
}
