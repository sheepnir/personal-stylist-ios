import Foundation

/// Owns `Documents/WearingPhotos/` (ADR-0004). Nothing else writes or deletes here, and
/// this store never touches garment, profile or fixture files.
///
/// Files are `{uuid}.jpg`, written atomically with `NSFileProtectionComplete` and excluded
/// from backup — the same policy as `UserGarmentPhotoStore`.
struct WearingPhotoFileStore: Sendable {
    static let directoryName = "WearingPhotos"

    let directory: URL
    let files: FileOperating

    init(directory: URL? = nil, files: FileOperating = SystemFileOperations()) {
        self.directory = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        self.files = files
    }

    /// Store for tests and previews: a unique temporary directory.
    static func temporary(files: FileOperating = SystemFileOperations()) -> WearingPhotoFileStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WearingPhotos-\(UUID().uuidString)", isDirectory: true)
        return WearingPhotoFileStore(directory: dir, files: files)
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    func exists(_ id: UUID) -> Bool {
        files.fileExists(atPath: fileURL(for: id).path)
    }

    func data(for id: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: id), options: .mappedIfSafe)
    }

    /// Write `data` under a new id. A failure leaves no partial file behind.
    func write(_ data: Data) throws -> UUID {
        let id = UUID()
        try ensureDirectory()
        let url = fileURL(for: id)
        do {
            try DurableFileWriter.writeAtomically(
                data,
                to: url,
                using: files,
                options: [.atomic, .completeFileProtection]
            )
            try Self.excludeFromBackup(url)
        } catch {
            try? files.removeItem(at: url)
            throw WearingPhotoPersistError.map(error)
        }
        return id
    }

    /// Best-effort delete. Missing files are fine; a failed delete is swept later.
    func remove(_ ids: [UUID]) {
        for id in Set(ids) {
            let url = fileURL(for: id)
            guard files.fileExists(atPath: url.path) else { continue }
            try? files.removeItem(at: url)
        }
    }

    /// Delete `{uuid}.jpg` files that no row references and that were not modified in the
    /// last `minimumAge` seconds (so an in-flight add is never swept). Only this directory
    /// is inspected. Returns the removed ids.
    @discardableResult
    func sweepOrphans(referenced: Set<UUID>, minimumAge: TimeInterval = 600, now: Date = Date()) -> [UUID] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var removed: [UUID] = []
        for url in urls where url.pathExtension.lowercased() == "jpg" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !referenced.contains(id) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) >= minimumAge else { continue }
            if (try? files.removeItem(at: url)) != nil {
                removed.append(id)
            }
        }
        return removed
    }

    private func ensureDirectory() throws {
        if files.fileExists(atPath: directory.path) { return }
        try files.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try Self.excludeFromBackup(directory)
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }
}
