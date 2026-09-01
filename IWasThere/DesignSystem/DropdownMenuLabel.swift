import SwiftUI

/// Trailing label for menu-style dropdowns (Games, Leaders, Settings, Home).
struct DropdownMenuLabel: View {
    enum Style {
        /// Trailing value on a settings row.
        case compact
        /// Home league chip — larger tap target and type.
        case chip
    }

    let title: String
    var style: Style = .compact

    var body: some View {
        HStack(spacing: spacing) {
            Text(verbatim: title)
                .font(titleFont)
                .foregroundStyle(DesignTokens.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
            if style == .compact {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
            } else {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
            }
        }
    }

    private var spacing: CGFloat {
        switch style {
        case .compact: 6
        case .chip: 8
        }
    }

    private var titleFont: Font {
        switch style {
        case .compact: .subheadline.weight(.semibold)
        case .chip: .body.weight(.semibold)
        }
    }
}
