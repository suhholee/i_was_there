import Foundation

/// Baseball Reference / MLB rate formulas over counting stats.
/// Prefer summing counts across games, then dividing (never average of averages).
enum StatFormulas {
    // MARK: - Batting

    /// AVG = H / AB
    static func battingAverage(hits: Int, atBats: Int) -> Double? {
        guard atBats > 0 else { return nil }
        return Double(hits) / Double(atBats)
    }

    /// OBP = (H + BB + HBP) / (AB + BB + HBP + SF)
    static func onBasePercentage(
        hits: Int,
        walks: Int,
        hitByPitch: Int,
        atBats: Int,
        sacFlies: Int
    ) -> Double? {
        let numerator = hits + walks + hitByPitch
        let denominator = atBats + walks + hitByPitch + sacFlies
        guard denominator > 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }

    /// SLG = TB / AB
    static func slugging(totalBases: Int, atBats: Int) -> Double? {
        guard atBats > 0 else { return nil }
        return Double(totalBases) / Double(atBats)
    }

    /// OPS = OBP + SLG
    static func ops(
        hits: Int,
        walks: Int,
        hitByPitch: Int,
        atBats: Int,
        sacFlies: Int,
        totalBases: Int
    ) -> Double? {
        guard
            let obp = onBasePercentage(
                hits: hits,
                walks: walks,
                hitByPitch: hitByPitch,
                atBats: atBats,
                sacFlies: sacFlies
            ),
            let slg = slugging(totalBases: totalBases, atBats: atBats)
        else { return nil }
        return obp + slg
    }

    /// ISO = SLG − AVG
    static func isolatedPower(totalBases: Int, hits: Int, atBats: Int) -> Double? {
        guard
            let slg = slugging(totalBases: totalBases, atBats: atBats),
            let avg = battingAverage(hits: hits, atBats: atBats)
        else { return nil }
        return slg - avg
    }

    /// BABIP ≈ (H − HR) / (AB − K − HR + SF)
    static func babip(
        hits: Int,
        homeRuns: Int,
        atBats: Int,
        strikeouts: Int,
        sacFlies: Int
    ) -> Double? {
        let numerator = hits - homeRuns
        let denominator = atBats - strikeouts - homeRuns + sacFlies
        guard denominator > 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }

    // MARK: - Pitching

    /// Innings pitched from outs (3 outs = 1 IP).
    static func inningsPitched(fromOuts outs: Int) -> Double {
        Double(outs) / 3.0
    }

    /// Parse MLB `inningsPitched` strings like `"5.1"` / `"5.2"` (outs notation).
    static func outs(fromInningsPitched string: String?) -> Int? {
        guard let string, !string.isEmpty else { return nil }
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(parts[0]) else { return nil }
        let fractionalOuts: Int
        if parts.count > 1, let frac = Int(parts[1]) {
            fractionalOuts = min(max(frac, 0), 2)
        } else {
            fractionalOuts = 0
        }
        return whole * 3 + fractionalOuts
    }

    /// ERA = 9 × ER / IP
    static func era(earnedRuns: Int, outs: Int) -> Double? {
        guard outs > 0 else { return nil }
        let ip = inningsPitched(fromOuts: outs)
        return 9.0 * Double(earnedRuns) / ip
    }

    /// WHIP = (H + BB) / IP
    static func whip(hits: Int, walks: Int, outs: Int) -> Double? {
        guard outs > 0 else { return nil }
        let ip = inningsPitched(fromOuts: outs)
        return Double(hits + walks) / ip
    }

    /// K/9 = 9 × K / IP
    static func strikeoutsPerNine(strikeouts: Int, outs: Int) -> Double? {
        guard outs > 0 else { return nil }
        let ip = inningsPitched(fromOuts: outs)
        return 9.0 * Double(strikeouts) / ip
    }

    /// BB/9 = 9 × BB / IP
    static func walksPerNine(walks: Int, outs: Int) -> Double? {
        guard outs > 0 else { return nil }
        let ip = inningsPitched(fromOuts: outs)
        return 9.0 * Double(walks) / ip
    }

    // MARK: - Formatting

    static func formatRate(_ value: Double?, digits: Int = 3) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    /// Batting average style without leading zero: .312
    static func formatAverage(_ value: Double?) -> String {
        guard let value else { return "—" }
        let clamped = String(format: "%.3f", value)
        if clamped.hasPrefix("0") {
            return String(clamped.dropFirst())
        }
        return clamped
    }

    /// Win percentage with leading zero and three decimals: `0.450`.
    static func formatWinPercentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.3f", value)
    }

    /// Normalize API win% strings (`.450`, `0.45`, `0.450`) to `0.450`.
    static func formatWinPercentage(raw: String?) -> String {
        guard let raw else { return "—" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—" else { return "—" }
        let normalized: String
        if trimmed.hasPrefix(".") {
            normalized = "0" + trimmed
        } else {
            normalized = trimmed
        }
        guard let value = Double(normalized) else { return "—" }
        return formatWinPercentage(value)
    }

    static func formatIP(outs: Int) -> String {
        let whole = outs / 3
        let rem = outs % 3
        return "\(whole).\(rem)"
    }

    /// Estimate batters faced when the box score omits TBF (common in KBO feeds).
    static func estimatedBattersFaced(
        hits: Int,
        walks: Int,
        strikeouts: Int,
        outsRecorded: Int
    ) -> Int {
        let bipOuts = max(0, outsRecorded - strikeouts)
        return hits + walks + strikeouts + bipOuts
    }
}
