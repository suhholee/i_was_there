import SwiftUI

struct GamePhotoThumbnail: View {
    let relativePath: String

    var body: some View {
        Group {
            if let image = PhotoStore.loadImage(relativePath: relativePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    DesignTokens.surface
                    Image(systemName: "photo")
                        .foregroundStyle(DesignTokens.secondaryText)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    }
}
