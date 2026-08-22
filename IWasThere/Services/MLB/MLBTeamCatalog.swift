import Foundation

struct MLBTeamInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let abbreviation: String
}

/// Static MLB club list for favorite-team + filters (IDs match Stats API).
enum MLBTeamCatalog {
    static let all: [MLBTeamInfo] = [
        .init(id: 108, name: "Los Angeles Angels", abbreviation: "LAA"),
        .init(id: 109, name: "Arizona Diamondbacks", abbreviation: "AZ"),
        .init(id: 110, name: "Baltimore Orioles", abbreviation: "BAL"),
        .init(id: 111, name: "Boston Red Sox", abbreviation: "BOS"),
        .init(id: 112, name: "Chicago Cubs", abbreviation: "CHC"),
        .init(id: 113, name: "Cincinnati Reds", abbreviation: "CIN"),
        .init(id: 114, name: "Cleveland Guardians", abbreviation: "CLE"),
        .init(id: 115, name: "Colorado Rockies", abbreviation: "COL"),
        .init(id: 116, name: "Detroit Tigers", abbreviation: "DET"),
        .init(id: 117, name: "Houston Astros", abbreviation: "HOU"),
        .init(id: 118, name: "Kansas City Royals", abbreviation: "KC"),
        .init(id: 119, name: "Los Angeles Dodgers", abbreviation: "LAD"),
        .init(id: 120, name: "Washington Nationals", abbreviation: "WSH"),
        .init(id: 121, name: "New York Mets", abbreviation: "NYM"),
        .init(id: 133, name: "Oakland Athletics", abbreviation: "ATH"),
        .init(id: 134, name: "Pittsburgh Pirates", abbreviation: "PIT"),
        .init(id: 135, name: "San Diego Padres", abbreviation: "SD"),
        .init(id: 136, name: "Seattle Mariners", abbreviation: "SEA"),
        .init(id: 137, name: "San Francisco Giants", abbreviation: "SF"),
        .init(id: 138, name: "St. Louis Cardinals", abbreviation: "STL"),
        .init(id: 139, name: "Tampa Bay Rays", abbreviation: "TB"),
        .init(id: 140, name: "Texas Rangers", abbreviation: "TEX"),
        .init(id: 141, name: "Toronto Blue Jays", abbreviation: "TOR"),
        .init(id: 142, name: "Minnesota Twins", abbreviation: "MIN"),
        .init(id: 143, name: "Philadelphia Phillies", abbreviation: "PHI"),
        .init(id: 144, name: "Atlanta Braves", abbreviation: "ATL"),
        .init(id: 145, name: "Chicago White Sox", abbreviation: "CWS"),
        .init(id: 146, name: "Miami Marlins", abbreviation: "MIA"),
        .init(id: 147, name: "New York Yankees", abbreviation: "NYY"),
        .init(id: 158, name: "Milwaukee Brewers", abbreviation: "MIL")
    ].sorted { $0.name < $1.name }

    static func team(id: Int) -> MLBTeamInfo? {
        all.first { $0.id == id }
    }

    /// Favorite team first (with star in label), then the rest A–Z by name. No abbreviations.
    static func orderedForPicker(
        favoring favoriteID: Int?,
        from teams: [MLBTeamInfo] = all
    ) -> [MLBTeamInfo] {
        guard let favoriteID,
              let favorite = teams.first(where: { $0.id == favoriteID })
        else {
            return teams.sorted { $0.name < $1.name }
        }
        let others = teams.filter { $0.id != favoriteID }.sorted { $0.name < $1.name }
        return [favorite] + others
    }

    static func pickerLabel(for team: MLBTeamInfo, favoriteID: Int?) -> String {
        if let favoriteID, team.id == favoriteID {
            return "\(team.name) ★"
        }
        return team.name
    }
}
