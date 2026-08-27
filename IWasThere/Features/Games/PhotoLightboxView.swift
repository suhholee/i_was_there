import SwiftUI

/// Full-screen photo viewer centered on a dark dimmed background.
struct PhotoLightboxView: View {
    let relativePath: String
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            if let image = PhotoStore.loadImage(relativePath: relativePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            } else {
                ContentUnavailableView("Photo unavailable", systemImage: "photo")
                    .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .white.opacity(0.25))
                    }
                    .padding()
                }
                Spacer()
            }
        }
    }
}
