import SwiftUI
import UIKit

/// Loads a team mark for Home / headers. Uses URLSession (with User-Agent) because
/// plain `AsyncImage` often fails on device against MLB CDNs.
struct TeamLogoImage: View {
    let teamID: Int
    var size: CGFloat = 44

    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Circle()
                    .fill(TeamTheme.forTeamID(teamID).primary.opacity(0.55))
                    .overlay {
                        Text(MLBTeamCatalog.team(id: teamID)?.abbreviation ?? "")
                            .font(.system(size: size * 0.28, weight: .bold))
                            .foregroundStyle(.white)
                    }
            } else {
                Circle()
                    .fill(TeamTheme.forTeamID(teamID).primary.opacity(0.35))
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .frame(width: size, height: size)
        .task(id: teamID) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        uiImage = nil
        failed = false
        guard let candidates = MLBAssetURLs.teamLogoCandidates(teamID: teamID), !candidates.isEmpty else {
            failed = true
            return
        }
        for url in candidates {
            if let image = await Self.fetchImage(url: url) {
                uiImage = image
                return
            }
        }
        failed = true
    }

    private static func fetchImage(url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.setValue("IWasThere/0.1 (prototype; local-first)", forHTTPHeaderField: "User-Agent")
        request.setValue("image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
