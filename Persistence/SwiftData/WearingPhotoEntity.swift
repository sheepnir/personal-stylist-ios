import Foundation
import SwiftData

// MARK: - Wearing photo (Sprint 9, ADR-0004)
//
// A local photo of the owner wearing one garment. Deliberately not a relationship:
// linking to `GarmentEntity` would change that live class and every stamped schema
// that lists it. `garmentId` is a plain value; garment delete / clear remove rows
// explicitly (SwiftDataPersistenceStore+Destructive). Files live only under
// `Documents/WearingPhotos/` and are owned by `WearingPhotoFileStore`.

@Model
final class WearingPhotoEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var garmentId: UUID
    /// Displayed (possibly cropped) JPEG — `WearingPhotos/{displayFileId}.jpg`.
    var displayFileId: UUID
    /// App-held source for re-editing. Nil only if the source could not be kept.
    var sourceFileId: UUID?
    /// Gallery order key, newest first. Never changed by editing.
    var addedAt: Date
    var updatedAt: Date
    /// CAMERA | LIBRARY
    var sourceRaw: String
    /// SAVED | FAILED | nil (not requested). Camera captures only.
    var photosExportRaw: String?

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        garmentId: UUID,
        displayFileId: UUID,
        sourceFileId: UUID?,
        addedAt: Date = Date(),
        updatedAt: Date? = nil,
        sourceRaw: String,
        photosExportRaw: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.garmentId = garmentId
        self.displayFileId = displayFileId
        self.sourceFileId = sourceFileId
        self.addedAt = addedAt
        self.updatedAt = updatedAt ?? addedAt
        self.sourceRaw = sourceRaw
        self.photosExportRaw = photosExportRaw
    }
}
