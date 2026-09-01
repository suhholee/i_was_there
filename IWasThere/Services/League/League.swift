import Foundation

/// Active sport / diary partition. MLB and KBO data stay separate on device.
enum League: String, CaseIterable, Identifiable, Codable, Sendable {
    case mlb
    case kbo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mlb: "MLB"
        case .kbo: "KBO"
        }
    }

    var apiLabel: String {
        switch self {
        case .mlb: "MLB Stats API"
        case .kbo: "Sports2i KBO"
        }
    }

    /// Practical earliest season for Add Game with box lines (KBO box ≈ 2019+).
    var earliestImportSeason: Int {
        switch self {
        case .mlb: 1900
        case .kbo: 2019
        }
    }
}

enum LeagueKey {
    static func mlb(_ gamePk: Int) -> String { "mlb:\(gamePk)" }
    static func kbo(_ gameID: String) -> String { "kbo:\(gameID)" }

    /// Stable Int for PhotoStore folders / legacy `mlbGamePk` uniqueness when storing KBO games.
    static func syntheticPk(forKBOGameID gameID: String) -> Int {
        var hash: UInt64 = 5381
        for byte in gameID.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let masked = Int(hash & 0x0FFF_FFFF)
        return 0x7000_0000 | masked
    }
}
