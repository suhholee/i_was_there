import Foundation

struct KBOTeamInfo: Identifiable, Hashable, Sendable {
    /// Synthetic Int id for SwiftData / TeamTheme (stable across app versions).
    let id: Int
    let code: String
    let name: String
    let abbreviation: String
    /// Default home ballpark when the API omits stadium name.
    let homeStadiumName: String

    /// Asset catalog name (`kbo_HH`, …) in `Assets.xcassets`.
    var logoAssetName: String { "kbo_\(code)" }
}

/// KBO first-team clubs (`le_id=1`). Codes match Sports2i `t_id` / `h_t_id` / `a_t_id`.
enum KBOTeamCatalog {
    static let all: [KBOTeamInfo] = [
        .init(id: 9101, code: "HH", name: "Hanwha Eagles", abbreviation: "HH", homeStadiumName: "대전 한화생명 볼파크"),
        .init(id: 9102, code: "HT", name: "KIA Tigers", abbreviation: "KIA", homeStadiumName: "광주 기아 챔피언스 필드"),
        .init(id: 9103, code: "KT", name: "KT Wiz", abbreviation: "KT", homeStadiumName: "수원 KT 위즈 파크"),
        .init(id: 9104, code: "LG", name: "LG Twins", abbreviation: "LG", homeStadiumName: "서울종합운동장 야구장"),
        .init(id: 9105, code: "LT", name: "Lotte Giants", abbreviation: "LOT", homeStadiumName: "사직 야구장"),
        .init(id: 9106, code: "NC", name: "NC Dinos", abbreviation: "NC", homeStadiumName: "창원 NC 파크"),
        .init(id: 9107, code: "OB", name: "Doosan Bears", abbreviation: "DOO", homeStadiumName: "서울종합운동장 야구장"),
        .init(id: 9108, code: "SK", name: "SSG Landers", abbreviation: "SSG", homeStadiumName: "인천 SSG 랜더스필드"),
        .init(id: 9109, code: "SS", name: "Samsung Lions", abbreviation: "SAM", homeStadiumName: "대구 삼성 라이온즈 파크"),
        .init(id: 9110, code: "WO", name: "Kiwoom Heroes", abbreviation: "KIW", homeStadiumName: "고척 스카이돔")
    ].sorted { $0.name < $1.name }

    private static let byCode: [String: KBOTeamInfo] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })
    }()

    private static let byID: [Int: KBOTeamInfo] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    static func team(code: String) -> KBOTeamInfo? {
        byCode[code.uppercased()]
    }

    static func team(id: Int) -> KBOTeamInfo? {
        byID[id]
    }

    static func id(forCode code: String) -> Int {
        team(code: code)?.id ?? 9199
    }

    static func displayName(code: String) -> String {
        team(code: code)?.name ?? code
    }

    static func orderedForPicker(favoring favoriteID: Int?) -> [KBOTeamInfo] {
        guard let favoriteID, let favorite = team(id: favoriteID) else {
            return all
        }
        return [favorite] + all.filter { $0.id != favoriteID }
    }

    static func pickerLabel(for team: KBOTeamInfo, favoriteID: Int?) -> String {
        if let favoriteID, team.id == favoriteID {
            return "\(team.name) ★"
        }
        return team.name
    }

    static func logoAssetName(forTeamID teamID: Int) -> String? {
        team(id: teamID)?.logoAssetName
    }

    /// Home ballpark for the given club; used when Sports2i omits stadium name.
    static func homeStadiumName(forTeamID teamID: Int) -> String? {
        team(id: teamID)?.homeStadiumName
    }

    static func homeStadiumName(forCode code: String) -> String? {
        team(code: code)?.homeStadiumName
    }

    /// Prefer canonical ballpark name from API code/label; fall back to home team default.
    static func resolvedVenueName(
        apiName: String,
        stadiumCode: String = "",
        homeTeamCode: String,
        homeTeamID: Int
    ) -> String {
        KBOStadiumCatalog.canonicalName(
            stadiumCode: stadiumCode,
            apiName: apiName,
            homeTeamCode: homeTeamCode,
            homeTeamID: homeTeamID
        )
    }
}
