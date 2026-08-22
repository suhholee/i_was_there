import Foundation

/// Team logo URLs are not in Stats API JSON. MLB publishes static assets separately.
enum MLBAssetURLs {
    static func teamLogoSVG(teamID: Int) -> URL? {
        URL(string: "https://www.mlbstatic.com/team-logos/\(teamID).svg")
    }

    /// Raster cap/spot mark suitable for `AsyncImage` (SVG often fails in UIKit).
    static func teamSpotImage(teamID: Int, size: Int = 72) -> URL? {
        URL(string: "https://midfield.mlbstatic.com/v1/team/\(teamID)/spots/\(size)")
    }
}
