import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \AttendedGame.gameDate, order: .reverse) private var games: [AttendedGame]
    @Query private var profiles: [UserProfile]
    @State private var showingAddGame = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("#iWasThere")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.primaryText)

                    Text("Your MLB 직관 log — attendance-scoped stats now; season WAR/wRC+ with a season filter in Phase 3.")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.secondaryText)

                    Button {
                        showingAddGame = true
                    } label: {
                        Label("Add game", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(DesignTokens.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    placeholderCard(
                        title: "Favorite team",
                        body: profile?.favoriteTeamAbbr.map { "Following \($0) — green WIN on games they won." }
                            ?? "Pick a favorite team in Settings for WIN badges and attendance win %."
                    )

                    placeholderCard(
                        title: "Attendance",
                        body: games.isEmpty
                            ? "No games logged yet."
                            : "\(games.count) game\(games.count == 1 ? "" : "s") logged. Open Games to see box lines and computed AVG/OPS/ERA."
                    )

                    if let latest = games.first {
                        NavigationLink {
                            GameDetailView(game: latest)
                        } label: {
                            placeholderCard(
                                title: "Latest game",
                                body: "\(latest.awayTeamName) \(latest.awayScore)–\(latest.homeScore) \(latest.homeTeamName)"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingAddGame) {
                AddGameView()
            }
        }
    }

    private func placeholderCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DesignTokens.primaryText)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [UserProfile.self, AttendedGame.self, GamePlayerStat.self, GamePhoto.self], inMemory: true)
}
