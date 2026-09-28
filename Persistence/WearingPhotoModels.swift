import Darwin
import Foundation

/// How a wearing photo entered the app (ADR-0004).
enum WearingPhotoSource: String, Sendable, Equatable {
    case camera = "CAMERA"
    case library = "LIBRARY"
}

/// Outcome of the optional system Photos export. Separate from the local save.
enum WearingPhotoExportState: String, Sendable, Equatable {
    case saved = "SAVED"
    case failed = "FAILED"
}

/// UI/DTO view of one wearing photo. Local only — never part of an engine request.
struct StubWearingPhoto: Identifiable, Hashable, Sendable {
    var id: UUID
    var garmentId: UUID
    var displayFileId: UUID
    var sourceFileId: UUID?
    var addedAt: Date
    var updatedAt: Date
    var source: WearingPhotoSource
    var exportState: WearingPhotoExportState?

    /// File whose pixels should be re-edited. Falls back to the displayed file.
    var editSourceFileId: UUID { sourceFileId ?? displayFileId }
}

/// Newest added first; `id` breaks ties so the order is stable across fetches.
enum WearingPhotoOrdering {
    static func sorted(_ photos: [StubWearingPhoto]) -> [StubWearingPhoto] {
        photos.sorted { lhs, rhs in
            if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Gallery layout: the latest photo is featured, then up to `recentLimit` previews.
    static let recentLimit = 5
}

/// Everything the store needs to add one photo. `id` is chosen once per add flow so
/// a retried save is idempotent instead of creating a second association.
struct WearingPhotoAddRequest: Sendable {
    var id: UUID
    var garmentId: UUID
    var displayJPEG: Data
    var sourceJPEG: Data?
    var source: WearingPhotoSource
    var addedAt: Date

    init(
        id: UUID = UUID(),
        garmentId: UUID,
        displayJPEG: Data,
        sourceJPEG: Data?,
        source: WearingPhotoSource,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.garmentId = garmentId
        self.displayJPEG = displayJPEG
        self.sourceJPEG = sourceJPEG
        self.source = source
        self.addedAt = addedAt
    }
}

/// Typed gallery failures the UI maps to copy. Never a raw file-system string.
enum WearingPhotoPersistError: Error, Equatable, Sendable {
    case garmentUnavailable
    case photoUnavailable
    case lowStorage
    case saveFailed

    static func map(_ error: Error) -> WearingPhotoPersistError {
        if let persist = error as? WearingPhotoPersistError { return persist }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return .lowStorage }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return .lowStorage }
        return .saveFailed
    }
}
