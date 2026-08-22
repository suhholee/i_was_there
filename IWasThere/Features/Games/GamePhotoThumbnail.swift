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
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
