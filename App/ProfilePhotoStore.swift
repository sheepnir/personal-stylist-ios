import Darwin
import Foundation

/// A local avatar, deliberately separate from wardrobe files and network DTOs.
struct ProfilePhotoStore {
    enum StoreError: Error { case invalidImage, writeFailed }

    let directory: URL
    private var photoURL: URL { directory.appendingPathComponent("profile.jpg") }
    /// Sprint 9: app-held source (≤1600 px) for re-cropping without compounding loss.
    private var sourceURL: URL { directory.appendingPathComponent("profile-source.jpg") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ProfilePhoto", isDirectory: true)
    }

    func load() throws -> Data? {
        do { return try Data(contentsOf: photoURL) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }

    /// The source to re-edit from: the retained source, else the displayed picture
    /// (older installs kept only the 800 px display file).
    func loadEditSource() throws -> Data? {
        do { return try Data(contentsOf: sourceURL) }
        catch CocoaError.fileReadNoSuchFile { return try load() }
    }

    /// Finish all fallible preparation before the atomic replacement. An error
    /// never deletes the current photo. Re-encoding also strips source metadata.
    @discardableResult
    func replace(with source: Data) throws -> Data {
        guard source.count <= Self.maxInputBytes,
              let jpeg = UserGarmentPhotoStore.downscaledJPEGData(source, maxPixel: Self.displayMaxPixel) else {
            throw StoreError.invalidImage
        }
        guard let kept = UserGarmentPhotoStore.downscaledJPEGData(source, maxPixel: PhotoEditing.sourceMaxPixel) else {
            throw StoreError.invalidImage
        }
        return try commit(display: jpeg, newSource: kept)
    }

    /// Sprint 9 crop: `croppedDisplay` becomes the picture. `newSource` is the freshly picked
    /// photo, or nil to keep the existing source untouched (re-editing never re-encodes it).
    @discardableResult
    func replace(croppedDisplay: Data, newSource: Data?) throws -> Data {
        guard croppedDisplay.count <= Self.maxInputBytes,
              let jpeg = UserGarmentPhotoStore.downscaledJPEGData(croppedDisplay, maxPixel: Self.displayMaxPixel) else {
            throw StoreError.invalidImage
        }
        var kept: Data?
        if let newSource {
            guard newSource.count <= Self.maxInputBytes,
                  let bounded = UserGarmentPhotoStore.downscaledJPEGData(newSource, maxPixel: PhotoEditing.sourceMaxPixel) else {
                throw StoreError.invalidImage
            }
            kept = bounded
        }
        return try commit(display: jpeg, newSource: kept)
    }

    func remove() throws {
        do { try FileManager.default.removeItem(at: photoURL) }
        catch CocoaError.fileNoSuchFile { }
        try? FileManager.default.removeItem(at: sourceURL)
    }

    private static let maxInputBytes = 30 * 1024 * 1024
    private static let displayMaxPixel = 800

    private func commit(display jpeg: Data, newSource: Data?) throws -> Data {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(excluded)
        let fm = FileManager.default

        // Stage every new file first; nothing live changes until they all exist.
        let stagedDisplay = try stage(jpeg, excluded: excluded)
        defer { try? fm.removeItem(at: stagedDisplay) }
        var stagedSource: URL?
        if let newSource {
            stagedSource = try stage(newSource, excluded: excluded)
        } else if !fm.fileExists(atPath: sourceURL.path), let previous = try? Data(contentsOf: photoURL) {
            // First edit of a pre-Sprint 9 picture: keep its uncropped pixels as the source.
            stagedSource = try stage(previous, excluded: excluded)
        }
        defer { if let stagedSource { try? fm.removeItem(at: stagedSource) } }

        // A new picture's source replaces the old one. Drop the old source first: if the app
        // stops between the renames, re-editing falls back to the displayed picture instead
        // of silently reverting to the previous photo.
        if newSource != nil {
            try? fm.removeItem(at: sourceURL)
        }
        // Same-directory rename is atomic, including replacement of an existing file.
        guard rename(stagedDisplay.path, photoURL.path) == 0 else { throw StoreError.writeFailed }
        if let stagedSource, rename(stagedSource.path, sourceURL.path) != 0 {
            // Never leave a source that no longer matches the picture's lineage.
            try? fm.removeItem(at: sourceURL)
        }
        return jpeg
    }

    private func stage(_ data: Data, excluded: URLResourceValues) throws -> URL {
        let staged = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        try data.write(to: staged, options: [.atomic, .completeFileProtection])
        var protected = staged
        try protected.setResourceValues(excluded)
        return staged
    }
}
