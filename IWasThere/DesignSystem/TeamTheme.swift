import SwiftUI

/// Local brand colors keyed by MLB `teamID` (Stats API has no reliable palette).
struct TeamTheme: Equatable {
    let teamID: Int?
    let primary: Color
    let secondary: Color
    let accent: Color

    static let `default` = TeamTheme(
        teamID: nil,
        primary: DesignTokens.surface,
        secondary: DesignTokens.background,
        accent: DesignTokens.accent
    )

    static func forTeamID(_ id: Int?) -> TeamTheme {
        guard let id, let palette = catalog[id] else { return .default }
        return TeamTheme(
            teamID: id,
            primary: Color(hex: palette.primary),
            secondary: Color(hex: palette.secondary),
            accent: Color(hex: palette.accent)
        )
    }

    private struct Palette {
        let primary: UInt32
        let secondary: UInt32
        let accent: UInt32
    }

    /// Approximate club colors for accents / jersey cards (not official brand PDFs).
    private static let catalog: [Int: Palette] = [
        108: .init(primary: 0xBA0021, secondary: 0x003263, accent: 0xC4CED4), // LAA
        109: .init(primary: 0xA71930, secondary: 0xE3D4AD, accent: 0x000000), // AZ
        110: .init(primary: 0xDF4601, secondary: 0x000000, accent: 0xA2AAAD), // BAL
        111: .init(primary: 0xBD3039, secondary: 0x0C2340, accent: 0xFFFFFF), // BOS
        112: .init(primary: 0x0E3386, secondary: 0xCC3433, accent: 0xFFFFFF), // CHC
        113: .init(primary: 0xC6011F, secondary: 0x000000, accent: 0xFFFFFF), // CIN
        114: .init(primary: 0x00385D, secondary: 0xE50022, accent: 0xFFFFFF), // CLE
        115: .init(primary: 0x33006F, secondary: 0xC4CED4, accent: 0xFFFFFF), // COL
        116: .init(primary: 0x0C2340, secondary: 0xFA4616, accent: 0xFFFFFF), // DET
        117: .init(primary: 0x002D62, secondary: 0xEB6E1F, accent: 0xFFFFFF), // HOU
        118: .init(primary: 0x004687, secondary: 0xBD9B60, accent: 0xFFFFFF), // KC
        119: .init(primary: 0x005A9C, secondary: 0xEF3E42, accent: 0xFFFFFF), // LAD
        120: .init(primary: 0xAB0003, secondary: 0x14225A, accent: 0xFFFFFF), // WSH
        121: .init(primary: 0x002D72, secondary: 0xFF5910, accent: 0xFFFFFF), // NYM
        133: .init(primary: 0x003831, secondary: 0xEFB21E, accent: 0xFFFFFF), // ATH
        134: .init(primary: 0x27251F, secondary: 0xFDB827, accent: 0xFFFFFF), // PIT
        135: .init(primary: 0x2F241D, secondary: 0xFFC425, accent: 0xFFFFFF), // SD
        136: .init(primary: 0x0C2C56, secondary: 0x005C5C, accent: 0xC4CED4), // SEA
        137: .init(primary: 0xFD5A1E, secondary: 0x27251F, accent: 0xFFFFFF), // SF
        138: .init(primary: 0xC41E3A, secondary: 0x0C2340, accent: 0xFFFFFF), // STL
        139: .init(primary: 0x092C5C, secondary: 0x8FBCE6, accent: 0xF5D130), // TB
        140: .init(primary: 0x003278, secondary: 0xC0111F, accent: 0xFFFFFF), // TEX
        141: .init(primary: 0x134A8E, secondary: 0x1D2D5C, accent: 0xE8291C), // TOR
        142: .init(primary: 0x002B5C, secondary: 0xD31145, accent: 0xFFFFFF), // MIN
        143: .init(primary: 0xE81828, secondary: 0x002D72, accent: 0xFFFFFF), // PHI
        144: .init(primary: 0xCE1141, secondary: 0x13274F, accent: 0xFFFFFF), // ATL
        145: .init(primary: 0x27251F, secondary: 0xC4CED4, accent: 0xFFFFFF), // CWS
        146: .init(primary: 0x00A3E0, secondary: 0xEF3340, accent: 0x000000), // MIA
        147: .init(primary: 0x0C2340, secondary: 0xC4CED3, accent: 0xFFFFFF), // NYY
        158: .init(primary: 0xFFC52F, secondary: 0x12284B, accent: 0xFFFFFF), // MIL
        // KBO (synthetic ids from KBOTeamCatalog)
        9101: .init(primary: 0xFF6600, secondary: 0x000000, accent: 0xFFFFFF), // HH Hanwha
        9102: .init(primary: 0xEA0029, secondary: 0x000000, accent: 0xFFFFFF), // HT KIA
        9103: .init(primary: 0x000000, secondary: 0xEB1C24, accent: 0xFFFFFF), // KT
        9104: .init(primary: 0xC3043F, secondary: 0x000000, accent: 0xFFFFFF), // LG
        9105: .init(primary: 0x041E42, secondary: 0xED1C24, accent: 0xFFFFFF), // LT Lotte
        9106: .init(primary: 0x315288, secondary: 0xC4A574, accent: 0xFFFFFF), // NC
        9107: .init(primary: 0x131230, secondary: 0xED1C24, accent: 0xFFFFFF), // OB Doosan
        9108: .init(primary: 0xCE0E2D, secondary: 0x000000, accent: 0xFFFFFF), // SK SSG
        9109: .init(primary: 0x074CA1, secondary: 0xC0C0C0, accent: 0xFFFFFF), // SS Samsung
        9110: .init(primary: 0x820024, secondary: 0x000000, accent: 0xFFFFFF)  // WO Kiwoom
    ]
}

private struct TeamThemeKey: EnvironmentKey {
    static let defaultValue = TeamTheme.default
}

extension EnvironmentValues {
    var teamTheme: TeamTheme {
        get { self[TeamThemeKey.self] }
        set { self[TeamThemeKey.self] = newValue }
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
