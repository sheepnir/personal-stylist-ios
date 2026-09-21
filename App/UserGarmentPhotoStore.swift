import Darwin
import Foundation
import ImageIO
import UIKit

/// Local-only garment photos (Documents/GarmentPhotos). Never sent off-device.
/// Stored with `NSFileProtectionComplete` and excluded from iCloud/iTunes backup
/// (PRD §12.4, M1-INF-06, #173).
enum UserGarmentPhotoStore {
    static let pathPrefix = "user-photo:"
    /// Durable camera capture before a garment exists (D-73). Same file as `user-photo:{id}`.
    static let pendingPathPrefix = "pending-photo:"
    /// D-74 replacement JPEG staged under a new id. Same file as `user-photo:{id}`.
    static let replacePathPrefix = "replace-photo:"
    /// Longest edge stored on disk (#156). Grid cells never need camera-native pixels.
    static let maxStoredPixel = 1600

    enum StoreError: Error, Equatable {
        case undecodable
        case encodeFailed
        case lowStorage
        case writeFailed
    }

    private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func persistJPEG(from data: Data, garmentId: UUID) throws -> String {
        try writeProtectedJPEG(from: data, id: garmentId)
        return userPhotoPath(for: garmentId)
    }

    /// Same protection / orientation / downscale as the library path, tagged pending until commit.
    static func persistPendingJPEG(from data: Data, captureId: UUID) throws -> String {
        try writeProtectedJPEG(from: data, id: captureId)
        return pendingPhotoPath(for: captureId)
    }

    /// D-74 — write the replacement under a **new** id. Never the live garment id.
    static func persistReplaceJPEG(from data: Data, stagingId: UUID) throws -> String {
        try writeProtectedJPEG(from: data, id: stagingId)
        return replacePhotoPath(for: stagingId)
    }

    static func userPhotoPath(for id: UUID) -> String {
        pathPrefix + id.uuidString
    }

    static func pendingPhotoPath(for id: UUID) -> String {
        pendingPathPrefix + id.uuidString
    }

    static func replacePhotoPath(for id: UUID) -> String {
        replacePathPrefix + id.uuidString
    }

    private static func writeProtectedJPEG(from data: Data, id: UUID) throws {
        guard let image = downsampledImage(data, maxPixel: maxStoredPixel) else {
            throw StoreError.undecodable
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else {
            throw StoreError.encodeFailed
        }
        let url = try fileURL(forGarmentId: id)
        do {
            try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
            try applyProtectionAndExcludeFromBackup(at: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw mapWriteError(error)
        }
        thumbnails.removeAllObjects()
    }

    private static func mapWriteError(_ error: Error) -> StoreError {
        if let store = error as? StoreError { return store }
        let ns = error as NSError
        if ns.code == NSFileWriteOutOfSpaceError { return .lowStorage }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return .lowStorage }
        return .writeFailed
    }

    /// ImageIO thumbnail — does not decode the full bitmap (#155, #156).
    static func downscaledJPEGData(_ data: Data, maxPixel: Int, quality: CGFloat = 0.82) -> Data? {
        guard let image = downsampledImage(data, maxPixel: maxPixel) else { return nil }
        return image.jpegData(compressionQuality: quality)
    }

    /// Cached display bitmap. `maxPixel` should match the on-screen point size times the screen scale.
    static func loadThumbnail(imagePath: String?, maxPixel: Int) -> UIImage? {
        guard let url = resolvedFileURL(imagePath) else { return nil }
        let pixel = max(64, maxPixel)
        let key = "\(url.path)#\(pixel)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let image = downsampledImage(data, maxPixel: pixel) else { return nil }
        thumbnails.setObject(image, forKey: key, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }

    static func isUserPhoto(_ imagePath: String?) -> Bool {
        resolvedFileURL(imagePath) != nil
    }

    /// Best-effort delete of `Documents/GarmentPhotos/{id}.jpg` and the `user-photo:` path. Safe if missing.
    static func removeFiles(forGarmentId id: UUID) {
        removeFile(imagePath: pathPrefix + id.uuidString)
        if let url = try? fileURL(forGarmentId: id) {
            evictThumbnails()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Delete a user-owned photo if `imagePath` is `user-photo:` or a file URL. Never touches bundle fixtures.
    static func removeFile(imagePath: String?) {
        guard let imagePath, !imagePath.isEmpty, isOwnedUserFile(imagePath) else { return }
        evictThumbnails()
        if let url = ownedFileURL(imagePath) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Owned photos for this garment: the `user-photo:` file plus any extra paths not referenced elsewhere.
    /// `isOwnedUserFile` is only the fixture gate. Shared-reference protection is `referencedByOthers`.
    static func deleteOwnedFiles(
        for garmentId: UUID,
        additionalPaths: [String] = [],
        excluding referencedByOthers: Set<String> = []
    ) {
        let primary = userPhotoPath(for: garmentId)
        if !referencedByOthers.contains(primary) {
            removeFiles(forGarmentId: garmentId)
        }
        for path in Set(additionalPaths) where !referencedByOthers.contains(path) {
            removeFile(imagePath: path)
        }
    }

    static func evictThumbnails() {
        thumbnails.removeAllObjects()
    }

    /// `user-photo:` / `pending-photo:` / `replace-photo:` or a path under Documents/GarmentPhotos.
    /// Bundle-relative fixture SVGs return false. Shared-reference protection is `referencedByOthers`.
    static func isOwnedUserFile(_ imagePath: String) -> Bool {
        if imagePath.hasPrefix(pathPrefix)
            || imagePath.hasPrefix(pendingPathPrefix)
            || imagePath.hasPrefix(replacePathPrefix) { return true }
        if imagePath.hasPrefix("file://"), let url = URL(string: imagePath) {
            return isUnderGarmentPhotos(url)
        }
        if imagePath.hasPrefix("/") {
            return isUnderGarmentPhotos(URL(fileURLWithPath: imagePath))
        }
        return false
    }

    private static func ownedFileURL(_ imagePath: String) -> URL? {
        if let id = photoID(from: imagePath) {
            return try? fileURL(forGarmentId: id)
        }
        if imagePath.hasPrefix("file://"), let url = URL(string: imagePath) {
            return url
        }
        if imagePath.hasPrefix("/") {
            return URL(fileURLWithPath: imagePath)
        }
        return nil
    }

    private static func isUnderGarmentPhotos(_ url: URL) -> Bool {
        guard let dir = try? directoryURL() else { return false }
        return url.path.hasPrefix(dir.path)
    }

    static func loadUIImage(imagePath: String?) -> UIImage? {
        loadThumbnail(imagePath: imagePath, maxPixel: maxStoredPixel)
    }

    private static func downsampledImage(_ data: Data, maxPixel: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func resolvedFileURL(_ imagePath: String?) -> URL? {
        guard let imagePath, !imagePath.isEmpty else { return nil }
        if let id = photoID(from: imagePath) {
            guard let url = try? fileURL(forGarmentId: id),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
        if imagePath.hasPrefix("file://"), let url = URL(string: imagePath),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if imagePath.hasPrefix("/") {
            let url = URL(fileURLWithPath: imagePath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func photoID(from imagePath: String) -> UUID? {
        if imagePath.hasPrefix(pathPrefix) {
            return UUID(uuidString: String(imagePath.dropFirst(pathPrefix.count)))
        }
        if imagePath.hasPrefix(pendingPathPrefix) {
            return UUID(uuidString: String(imagePath.dropFirst(pendingPathPrefix.count)))
        }
        if imagePath.hasPrefix(replacePathPrefix) {
            return UUID(uuidString: String(imagePath.dropFirst(replacePathPrefix.count)))
        }
        return nil
    }

    private static func fileURL(forGarmentId id: UUID) throws -> URL {
        let dir = try directoryURL()
        return dir.appendingPathComponent("\(id.uuidString).jpg")
    }

    private static let migrationLock = NSLock()
    private static var protectedDirectory: URL?

    private static func directoryURL() throws -> URL {
        migrationLock.lock()
        defer { migrationLock.unlock() }
        if let protectedDirectory { return protectedDirectory }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("GarmentPhotos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try applyProtectionAndExcludeFromBackup(at: dir)
        // Migrate any pre-existing files that lack protection / backup exclusion.
        try hardenExistingFiles(in: dir)
        protectedDirectory = dir
        return dir
    }

    private static func hardenExistingFiles(in directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in urls where url.pathExtension.lowercased() == "jpg" || url.hasDirectoryPath {
            try applyProtectionAndExcludeFromBackup(at: url)
        }
    }

    private static func applyProtectionAndExcludeFromBackup(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }
}
