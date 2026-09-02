import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatarView: View {
    var image: UIImage?
    var diameter: CGFloat = 96

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(DesignTokens.secondaryText.opacity(0.55))
                    .padding(diameter * 0.12)
                    .background(DesignTokens.surface)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(DesignTokens.secondaryText.opacity(0.25), lineWidth: 1)
        }
    }
}

struct ProfileAvatarPicker: View {
    @Binding var image: UIImage?
    var diameter: CGFloat = 112
    var showsActionLabel: Bool = true
    var actionLabelBottomPadding: CGFloat = 0

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ProfileAvatarView(image: image, diameter: diameter)
            }
            .buttonStyle(.plain)

            if showsActionLabel {
                actionLabel
                    .padding(.bottom, actionLabelBottomPadding)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    image = picked
                }
            }
        }
    }

    @ViewBuilder
    private var actionLabel: some View {
        if image != nil {
            Button("Remove image") {
                image = nil
                photoItem = nil
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.secondaryText)
            .buttonStyle(.plain)
        } else {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("Add profile image")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}

enum ProfileAvatarPersistence {
    static func apply(image: UIImage?, to profile: UserProfile) throws {
        if let image, let jpeg = PhotoStore.jpegData(from: image) {
            if !profile.avatarRelativePath.isEmpty {
                AvatarStore.delete(relativePath: profile.avatarRelativePath)
            }
            profile.avatarRelativePath = try AvatarStore.saveJPEG(jpeg)
            profile.avatarStoragePath = ""
            return
        }

        if !profile.avatarRelativePath.isEmpty {
            AvatarStore.delete(relativePath: profile.avatarRelativePath)
        }
        profile.avatarRelativePath = ""
        profile.avatarStoragePath = ""
    }

    static func loadImage(for profile: UserProfile) -> UIImage? {
        AvatarStore.loadImage(relativePath: profile.avatarRelativePath)
    }
}
