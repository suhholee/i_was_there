import Foundation
import UIKit

enum PhotoStore {
    private static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("GamePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func absoluteURL(relativePath: String) -> URL {
        rootDirectory.appendingPathComponent(relativePath)
    }

    /// Saves JPEG data under `gamePk/uuid.jpg` and returns the relative path for SwiftData.
    static func saveJPEG(_ data: Data, gamePk: Int) throws -> String {
        let folder = rootDirectory.appendingPathComponent("\(gamePk)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).jpg"
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return "\(gamePk)/\(name)"
    }

    static func delete(relativePath: String) {
        let url = absoluteURL(relativePath: relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    static func loadImage(relativePath: String) -> UIImage? {
        let url = absoluteURL(relativePath: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func jpegData(from image: UIImage, quality: CGFloat = 0.82) -> Data? {
        image.jpegData(compressionQuality: quality)
    }
}
