import Foundation

/// Maps Sports2i stadium codes / short Korean labels to canonical KBO ballpark names.
enum KBOStadiumCatalog {
    /// Sports2i `s_id` → display name.
    private static let canonicalByCode: [String: String] = [
        "MH": "인천 SSG 랜더스필드",
        "JS": "서울종합운동장 야구장",
        "CW": "창원 NC 파크",
        "DJ": "대전 한화생명 볼파크",
        "DK": "대구 삼성 라이온즈 파크",
        "GC": "고척 스카이돔",
        "KC": "광주 기아 챔피언스 필드",
        "SJ": "사직 야구장",
        "SW": "수원 KT 위즈 파크",
        "CJ": "청주종합운동장 야구장",
        "EC": "이천 베어스파크 야구장",
        "EL": "LG 챔피언스파크 야구장",
        "JJ": "제주 오라종합경기장 야구장",
        "KS": "군산월명종합운동장 야구장",
        "MS": "마산종합운동장 야구장",
        "PH": "포항야구장",
        "SD": "상동 야구장",
        "UL": "울산 문수 야구장"
    ]

    /// Sports2i `s_nm` (and common fragments) → display name.
    /// More specific fragments first (e.g. `이천(두산)` before `이천`).
    private static let canonicalByAPIName: [(fragment: String, name: String)] = [
        ("문학", "인천 SSG 랜더스필드"),
        ("잠실", "서울종합운동장 야구장"),
        ("창원", "창원 NC 파크"),
        ("한밭", "대전 한화생명 볼파크"),
        ("대전", "대전 한화생명 볼파크"),
        ("대구", "대구 삼성 라이온즈 파크"),
        ("고척", "고척 스카이돔"),
        ("광주", "광주 기아 챔피언스 필드"),
        ("사직", "사직 야구장"),
        ("수원", "수원 KT 위즈 파크"),
        ("이천(두산)", "이천 베어스파크 야구장"),
        ("이천(LG)", "LG 챔피언스파크 야구장"),
        ("청주", "청주종합운동장 야구장"),
        ("제주", "제주 오라종합경기장 야구장"),
        ("군산", "군산월명종합운동장 야구장"),
        ("마산", "마산종합운동장 야구장"),
        ("포항", "포항야구장"),
        ("상동", "상동 야구장"),
        ("울산", "울산 문수 야구장")
    ]

    /// Resolve a display-ready stadium name from API fields, then home-team fallback.
    static func canonicalName(
        stadiumCode: String,
        apiName: String,
        homeTeamCode: String,
        homeTeamID: Int
    ) -> String {
        let code = stadiumCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let mapped = canonicalByCode[code] {
            return mapped
        }

        let trimmed = apiName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let mapped = canonicalName(matchingAPIName: trimmed) {
            return mapped
        }

        if !trimmed.isEmpty {
            return trimmed
        }

        return KBOTeamCatalog.homeStadiumName(forCode: homeTeamCode)
            ?? KBOTeamCatalog.homeStadiumName(forTeamID: homeTeamID)
            ?? ""
    }

    /// Re-normalize a stored venue label (e.g. legacy `문학` rows).
    static func canonicalName(
        stadiumCode: String,
        storedVenueName: String,
        homeTeamID: Int
    ) -> String {
        let homeCode = KBOTeamCatalog.team(id: homeTeamID)?.code ?? ""
        return canonicalName(
            stadiumCode: stadiumCode,
            apiName: storedVenueName,
            homeTeamCode: homeCode,
            homeTeamID: homeTeamID
        )
    }

    private static func canonicalName(matchingAPIName apiName: String) -> String? {
        for entry in canonicalByAPIName where apiName.contains(entry.fragment) {
            return entry.name
        }
        return nil
    }
}
