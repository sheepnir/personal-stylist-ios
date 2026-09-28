import Foundation
import SwiftData

extension PhotoReplaceGate {
    /// Serializes wearing-photo add / edit / remove so repeated taps and retries cannot race.
    static let wearingPhotos = PhotoReplaceGate()
}

/// Sprint 9 wearing gallery (ADR-0004). Files first under new ids, then one context save;
/// any failure removes only this operation's new files. Previous files are removed only
/// after the save that stops referencing them succeeds.
extension SwiftDataPersistenceStore {
    func fetchWearingPhotos(garmentId: UUID) async -> [StubWearingPhoto] {
        let uid = userId
        let gid = garmentId
        let rows = (try? await performThrowingValue { context -> [StubWearingPhoto] in
            let fd = FetchDescriptor<WearingPhotoEntity>(
                predicate: #Predicate { $0.userId == uid && $0.garmentId == gid },
                sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
            )
            return try context.fetch(fd).map(StubEntityMapper.stub(from:))
        }) ?? []
        return WearingPhotoOrdering.sorted(rows)
    }

    func addWearingPhoto(_ request: WearingPhotoAddRequest) async throws -> StubWearingPhoto {
        try await PhotoReplaceGate.wearingPhotos.run {
            try await self.addWearingPhotoUnlocked(request)
        }
    }

    func updateWearingPhotoDisplay(id: UUID, displayJPEG: Data) async throws -> StubWearingPhoto {
        try await PhotoReplaceGate.wearingPhotos.run {
            try await self.updateWearingPhotoDisplayUnlocked(id: id, displayJPEG: displayJPEG)
        }
    }

    func removeWearingPhoto(id: UUID) async throws {
        try await PhotoReplaceGate.wearingPhotos.run {
            try await self.removeWearingPhotoUnlocked(id: id)
        }
    }

    func setWearingPhotoExportState(id: UUID, state: WearingPhotoExportState) async throws -> StubWearingPhoto {
        let uid = userId
        let photoId = id
        return try await performThrowingValue { context in
            let fd = FetchDescriptor<WearingPhotoEntity>(
                predicate: #Predicate { $0.userId == uid && $0.id == photoId }
            )
            guard let row = try context.fetch(fd).first else {
                throw WearingPhotoPersistError.photoUnavailable
            }
            if row.photosExportRaw != state.rawValue {
                row.photosExportRaw = state.rawValue
                try context.save()
            }
            return StubEntityMapper.stub(from: row)
        }
    }

    /// Launch-time cleanup of files left by a termination between write and commit.
    func sweepOrphanWearingPhotoFiles() async {
        let uid = userId
        guard let referenced = try? await performThrowingValue({ context -> Set<UUID> in
            let rows = try context.fetch(FetchDescriptor<WearingPhotoEntity>(
                predicate: #Predicate { $0.userId == uid }
            ))
            var ids = Set<UUID>()
            for row in rows {
                ids.insert(row.displayFileId)
                if let source = row.sourceFileId { ids.insert(source) }
            }
            return ids
        }) else { return }
        wearingPhotoFiles.sweepOrphans(referenced: referenced)
    }

    // MARK: - Unlocked

    private func addWearingPhotoUnlocked(_ request: WearingPhotoAddRequest) async throws -> StubWearingPhoto {
        let uid = userId
        let photoId = request.id
        let existing = try? await performThrowingValue { context -> StubWearingPhoto? in
            let fd = FetchDescriptor<WearingPhotoEntity>(predicate: #Predicate { $0.id == photoId })
            return try context.fetch(fd).first.map(StubEntityMapper.stub(from:))
        }
        if let existing {
            // Retried save of the same add flow: no second association, no new files.
            return existing
        }

        let files = wearingPhotoFiles
        let displayId = try files.write(request.displayJPEG)
        var sourceId: UUID?
        if let source = request.sourceJPEG {
            do {
                sourceId = try files.write(source)
            } catch {
                files.remove([displayId])
                throw WearingPhotoPersistError.map(error)
            }
        }
        let newFiles = [displayId] + (sourceId.map { [$0] } ?? [])

        if let injected = WearingPhotoPersistHooks.failBeforeMetadataCommit {
            WearingPhotoPersistHooks.failBeforeMetadataCommit = nil
            files.remove(newFiles)
            throw WearingPhotoPersistError.map(injected)
        }

        let garmentId = request.garmentId
        let capturedSourceId = sourceId
        do {
            return try await performThrowingValue { context in
                let garmentFD = FetchDescriptor<GarmentEntity>(
                    predicate: #Predicate { $0.userId == uid && $0.id == garmentId }
                )
                guard try context.fetch(garmentFD).first != nil else {
                    throw WearingPhotoPersistError.garmentUnavailable
                }
                let row = WearingPhotoEntity(
                    id: request.id,
                    userId: uid,
                    garmentId: garmentId,
                    displayFileId: displayId,
                    sourceFileId: capturedSourceId,
                    addedAt: request.addedAt,
                    sourceRaw: request.source.rawValue
                )
                context.insert(row)
                try context.save()
                return StubEntityMapper.stub(from: row)
            }
        } catch {
            files.remove(newFiles)
            throw WearingPhotoPersistError.map(error)
        }
    }

    private func updateWearingPhotoDisplayUnlocked(id: UUID, displayJPEG: Data) async throws -> StubWearingPhoto {
        let uid = userId
        let photoId = id
        let files = wearingPhotoFiles
        let newDisplayId = try files.write(displayJPEG)

        if let injected = WearingPhotoPersistHooks.failBeforeMetadataCommit {
            WearingPhotoPersistHooks.failBeforeMetadataCommit = nil
            files.remove([newDisplayId])
            throw WearingPhotoPersistError.map(injected)
        }

        do {
            let (photo, previousDisplayId) = try await performThrowingValue { context -> (StubWearingPhoto, UUID?) in
                let fd = FetchDescriptor<WearingPhotoEntity>(
                    predicate: #Predicate { $0.userId == uid && $0.id == photoId }
                )
                guard let row = try context.fetch(fd).first else {
                    throw WearingPhotoPersistError.photoUnavailable
                }
                let garmentId = row.garmentId
                let garmentFD = FetchDescriptor<GarmentEntity>(
                    predicate: #Predicate { $0.userId == uid && $0.id == garmentId }
                )
                guard try context.fetch(garmentFD).first != nil else {
                    throw WearingPhotoPersistError.garmentUnavailable
                }
                let previous = row.displayFileId
                row.displayFileId = newDisplayId
                // Keep the pre-edit pixels as the source if none was retained.
                if row.sourceFileId == nil {
                    row.sourceFileId = previous
                }
                row.updatedAt = Date()
                try context.save()
                let stillReferenced = row.sourceFileId == previous
                return (StubEntityMapper.stub(from: row), stillReferenced ? nil : previous)
            }
            if let previousDisplayId {
                files.remove([previousDisplayId])
            }
            return photo
        } catch {
            files.remove([newDisplayId])
            throw WearingPhotoPersistError.map(error)
        }
    }

    private func removeWearingPhotoUnlocked(id: UUID) async throws {
        let uid = userId
        let photoId = id
        let fileIds: [UUID]
        do {
            fileIds = try await performThrowingValue { context -> [UUID] in
                let fd = FetchDescriptor<WearingPhotoEntity>(
                    predicate: #Predicate { $0.userId == uid && $0.id == photoId }
                )
                guard let row = try context.fetch(fd).first else { return [] }
                let ids = [row.displayFileId] + (row.sourceFileId.map { [$0] } ?? [])
                context.delete(row)
                try context.save()
                return ids
            }
        } catch {
            throw WearingPhotoPersistError.map(error)
        }
        wearingPhotoFiles.remove(fileIds)
    }
}

/// Test-only seam for write-then-metadata rollback. Production leaves this nil.
enum WearingPhotoPersistHooks {
    static var failBeforeMetadataCommit: Error?

    static func reset() {
        failBeforeMetadataCommit = nil
    }
}
