import Foundation

/// Team logo URLs are not in Stats API JSON. MLB / ESPN publish static assets separately.
enum MLBAssetURLs {
    static func teamLogoSVG(teamID: Int) -> URL? {
        URL(string: "https://www.mlbstatic.com/team-logos/\(teamID).svg")
    }

    /// Raster cap/spot mark (PNG). Prefer this over SVG for UIKit/SwiftUI.
    static func teamSpotImage(teamID: Int, size: Int = 72) -> URL? {
        URL(string: "https://midfield.mlbstatic.com/v1/team/\(teamID)/spots/\(size)")
    }

    /// Ordered candidates for device loads (first success wins).
    static func teamLogoCandidates(teamID: Int, size: Int = 128) -> [URL]? {
        var urls: [URL] = []
        if let spot = teamSpotImage(teamID: teamID, size: size) {
            urls.append(spot)
        }
        if let spotSmall = teamSpotImage(teamID: teamID, size: 72) {
            urls.append(spotSmall)
        }
        // ESPN slug fallback (abbreviation → lowercase path segment).
        if let abbr = MLBTeamCatalog.team(id: teamID)?.abbreviation {
            let slug = espnSlug(for: abbr)
            if let espn = URL(string: "https://a.espncdn.com/i/teamlogos/mlb/500/\(slug).png") {
                urls.append(espn)
            }
        }
        return urls.isEmpty ? nil : urls
    }

    private static func espnSlug(for abbreviation: String) -> String {
        switch abbreviation.uppercased() {
        case "AZ": return "ari"
        case "CWS": return "chw"
        case "ATH", "OAK": return "oak"
        case "WSH": return "wsh"
        default: return abbreviation.lowercased()
        }
    }
}
