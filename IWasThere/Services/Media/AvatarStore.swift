import Foundation
import UIKit

enum AvatarStore {
    private static let fileName = "avatar.jpg"

    private static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ProfileAvatar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func absoluteURL(relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    @discardableResult
    static func saveJPEG(_ data: Data) throws -> String {
        let url = rootDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return fileName
    }

    static func delete(relativePath: String) {
        guard !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: absoluteURL(relativePath: relativePath))
    }

    static func loadImage(relativePath: String) -> UIImage? {
        guard !relativePath.isEmpty else { return nil }
        let url = absoluteURL(relativePath: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func cloudPath(for userId: UUID) -> String {
        "\(userId.uuidString)/\(fileName)"
    }
}
