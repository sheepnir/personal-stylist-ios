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
        fileSystem: BaselineFileSystem = FileManager.default,
        applicationSupport: URL? = nil,
        documents: URL? = nil
    ) throws {
        if defaults.bool(forKey: completedKey) { return }

        let support: URL
        let docs: URL
        if let applicationSupport, let documents {
            support = applicationSupport
            docs = documents
        } else {
            let fm = FileManager.default
            support = try applicationSupport
                ?? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            docs = try documents
                ?? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }

        try removeStoreFiles(in: support, fileSystem: fileSystem)
        try removePhotoDirectory(in: docs, fileSystem: fileSystem)

        SeedSuppression.suppressAutomaticWardrobeSeed(in: defaults)
        SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
        defaults.set(true, forKey: completedKey)
    }

    private static func removeStoreFiles(in directory: URL, fileSystem: BaselineFileSystem) throws {
        guard fileSystem.fileExists(atPath: directory.path) else { return }
        let name = AppModelContainer.storeName
        let contents = try fileSystem.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for url in contents {
            let last = url.lastPathComponent
            guard last == name || last.hasPrefix(name + ".") else { continue }
            try fileSystem.removeItem(at: url)
        }
    }

    private static func removePhotoDirectory(in documents: URL, fileSystem: BaselineFileSystem) throws {
        let photos = documents.appendingPathComponent(UserGarmentPhotoStore.directoryName, isDirectory: true)
        guard fileSystem.fileExists(atPath: photos.path) else { return }
        try fileSystem.removeItem(at: photos)
    }
}

protocol BaselineFileSystem {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL]
    func removeItem(at url: URL) throws
}

extension FileManager: BaselineFileSystem {}
