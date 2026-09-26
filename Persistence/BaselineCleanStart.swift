import Foundation

/// One clean start for build 2026092602.
///
/// The completed key is frozen. A later build must keep this same key and must not
/// add another reset. After the key is set, relaunch and every later update leave
/// the store, photos, profile, and wear history in place. Device credentials are
/// not touched. This is not a migration fallback: `AppModelContainer` never calls it.
enum BaselineCleanStart {
    static let baselineBuild = "2026092602"
    /// Permanent. Do not rename, and do not introduce a second clean-start key.
    static let completedKey = "baseline.2026092602.cleanStartCompleted"

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupport: URL? = nil,
        documents: URL? = nil
    ) throws {
        if defaults.bool(forKey: completedKey) { return }

        let support = try applicationSupport
            ?? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let docs = try documents
            ?? fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

        try removeStoreFiles(in: support, fileManager: fileManager)
        try removePhotoDirectory(in: docs, fileManager: fileManager)

        SeedSuppression.suppressAutomaticWardrobeSeed(in: defaults)
        SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
        defaults.set(true, forKey: completedKey)
    }

    private static func removeStoreFiles(in directory: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let name = AppModelContainer.storeName
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let last = url.lastPathComponent
            guard last == name || last.hasPrefix(name + ".") else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    private static func removePhotoDirectory(in documents: URL, fileManager: FileManager) throws {
        let photos = documents.appendingPathComponent(UserGarmentPhotoStore.directoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: photos.path) else { return }
        try fileManager.removeItem(at: photos)
    }
}
