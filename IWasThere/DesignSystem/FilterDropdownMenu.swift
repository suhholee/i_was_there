import SwiftUI

/// Full-width surface dropdown used on Games, Leaders filters, and Settings.
struct FilterDropdownMenu<MenuContent: View>: View {
    let title: String
    @ViewBuilder let menuContent: () -> MenuContent

    init(
        title: String,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.title = title
        self.menuContent = menuContent
    }

    var body: some View {
        Menu(content: menuContent) {
            HStack(spacing: 10) {
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DesignTokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .tint(DesignTokens.primaryText)
    }
}
