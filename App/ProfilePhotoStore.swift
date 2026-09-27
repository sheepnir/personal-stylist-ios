import Darwin
import Foundation

/// A local avatar, deliberately separate from wardrobe files and network DTOs.
struct ProfilePhotoStore {
    enum StoreError: Error { case invalidImage, writeFailed }

    let directory: URL
    private var photoURL: URL { directory.appendingPathComponent("profile.jpg") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ProfilePhoto", isDirectory: true)
    }

    func load() throws -> Data? {
        do { return try Data(contentsOf: photoURL) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }

    /// Finish all fallible preparation before the atomic replacement. An error
    /// never deletes the current photo. Re-encoding also strips source metadata.
    @discardableResult
    func replace(with source: Data) throws -> Data {
        guard source.count <= 30 * 1024 * 1024,
              let jpeg = UserGarmentPhotoStore.downscaledJPEGData(source, maxPixel: 800) else {
            throw StoreError.invalidImage
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(excluded)
        let staged = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: staged) }
        try jpeg.write(to: staged, options: [.atomic, .completeFileProtection])
        var protected = staged
        try protected.setResourceValues(excluded)
        // Same-directory rename is atomic, including replacement of an existing file.
        guard rename(staged.path, photoURL.path) == 0 else { throw StoreError.writeFailed }
        return jpeg
    }

    func remove() throws {
        do { try FileManager.default.removeItem(at: photoURL) }
        catch CocoaError.fileNoSuchFile { return }
    }
}
