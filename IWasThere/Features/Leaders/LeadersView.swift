import SwiftUI

struct LeadersView: View {
    @State private var segment: LeaderSegment = .batters

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Leaders", selection: $segment) {
                    ForEach(LeaderSegment.allCases) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ContentUnavailableView(
                    segment == .batters ? "Batter leaders" : "Pitcher leaders",
                    systemImage: "tshirt",
                    description: Text("Phase 3: attendance-scoped leaders (AVG/OPS/ERA…) plus a season dropdown for context stats (WAR, wOBA, wRC+, FIP).")
                )

                Spacer()
            }
            .padding(.top)
            .background(DesignTokens.background.ignoresSafeArea())
            .navigationTitle("Leaders")
        }
    }
}

private enum LeaderSegment: String, CaseIterable, Identifiable {
    case batters
    case pitchers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .batters: "Batters"
        case .pitchers: "Pitchers"
        }
    }
}

#Preview {
    LeadersView()
}
