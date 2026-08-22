import Foundation

/// Team logo URLs are not in Stats API JSON. MLB publishes static SVG/PNG assets separately.
enum MLBAssetURLs {
    static func teamLogoSVG(teamID: Int) -> URL? {
        URL(string: "https://www.mlbstatic.com/team-logos/\(teamID).svg")
    }
}
