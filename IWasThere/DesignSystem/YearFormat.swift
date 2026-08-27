import Foundation

/// Years must never use locale grouping (`2,016` → `2016`).
enum YearFormat {
    static func string(_ year: Int) -> String {
        String(year)
    }
}
