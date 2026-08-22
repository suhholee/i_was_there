import SwiftUI

/// Simplified jersey silhouette for Leaders / Home / game MVP.
struct JerseyCardView: View {
    let number: String
    let name: String
    let subtitle: String
    let valueLabel: String
    let theme: TeamTheme
    var compact: Bool = false
    /// When true, card uses a white background and stat text switches to dark.
    var lightBackground: Bool = false

    var body: some View {
        HStack(spacing: compact ? 12 : 16) {
            jerseySilhouette
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(compact ? .subheadline.weight(.bold) : .headline.weight(.bold))
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(valueLabel)
                .font(compact ? .title3.weight(.heavy) : .title2.weight(.heavy))
                .foregroundStyle(statColor)
                .monospacedDigit()
        }
        .padding(compact ? 12 : 16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.secondary.opacity(0.35), lineWidth: 1)
        )
    }

    private var statColor: Color {
        lightBackground ? DesignTokens.cardPrimaryText : DesignTokens.primaryText
    }

    @ViewBuilder
    private var cardBackground: some View {
        if lightBackground {
            DesignTokens.cardBackground
        } else {
            LinearGradient(
                colors: [theme.primary.opacity(0.55), DesignTokens.surface],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var jerseySilhouette: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.primary)
            Text(displayNumber)
                .font(.system(size: compact ? 22 : 28, weight: .black, design: .rounded))
                .foregroundStyle(theme.accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .frame(width: compact ? 52 : 64, height: compact ? 60 : 74)
    }

    private var displayNumber: String {
        let trimmed = number.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#" : trimmed
    }
}

#Preview {
    VStack {
        JerseyCardView(
            number: "17",
            name: "Shohei Ohtani",
            subtitle: "3 games · attendance OPS",
            valueLabel: "1.048",
            theme: TeamTheme.forTeamID(119)
        )
    }
    .padding()
    .background(DesignTokens.background)
}
