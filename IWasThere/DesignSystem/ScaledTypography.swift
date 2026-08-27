import SwiftUI

/// Semantic fonts that respect the user’s Dynamic Type setting.
enum ScaledTypography {
    static let heroScore = Font.system(.largeTitle, design: .default, weight: .heavy)
    static let record = Font.system(.title2, design: .default, weight: .heavy)
    static let recordPct = Font.system(.title3, design: .default, weight: .bold)
    static let jerseyStat = Font.system(.title2, design: .default, weight: .heavy)
    static let jerseyStatCompact = Font.system(.title3, design: .default, weight: .heavy)
    static let jerseyNumber = Font.system(.title, design: .rounded, weight: .black)
    static let jerseyNumberCompact = Font.system(.title3, design: .rounded, weight: .black)
}
