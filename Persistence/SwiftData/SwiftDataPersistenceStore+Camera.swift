import Foundation
import SwiftData

extension SwiftDataPersistenceStore {
    func beginCameraPending(jpegData: Data) async throws -> UUID {
        await CameraPersistHooks.awaitInjectedDelay()
        let id = UUID()
        let path: String
        do {
            path = try UserGarmentPhotoStore.persistPendingJPEG(from: jpegData, captureId: id)
        } catch {
            throw CameraPersistError.map(error)
        }
        CameraPersistHooks.lastPendingFilePath = path
        do {
            if let injected = CameraPersistHooks.failAfterPendingFileWrite {
                CameraPersistHooks.failAfterPendingFileWrite = nil
                throw injected
            }
            let uid = userId
            try await performThrowing { context in
                let batch = CaptureBatchEntity(
                    userId: uid,
                    sourceRaw: "CAMERA",
                    readingAllowed: false,
                    captureIds: [id]
                )
                context.insert(batch)
                context.insert(
                    PendingCaptureEntity(
                        id: id,
                        userId: uid,
                        batchId: batch.id,
                        masterURI: path,
                        imageStateRaw: "SAVED",
                        slotIntentRaw: nil,
                        analysisStateRaw: "NOT_REQUESTED",
                        reviewStateRaw: "PENDING",
                        garmentId: nil
                    )
                )
                try context.save()
            }
            return id
        } catch {
            UserGarmentPhotoStore.removeFile(imagePath: path)
            UserGarmentPhotoStore.removeFiles(forGarmentId: id)
            throw CameraPersistError.map(error)
        }
    }

    func abandonCameraPending(id: UUID) async throws {
        let uid = userId
        let cleanup = try await performThrowingValue { context -> PhotoCleanup in
            let cleanup = try Self.applyAbandonCameraPending(id: id, userId: uid, in: context)
            try context.save()
            return cleanup
        }
        cleanup.apply()
    }

    func commitCameraPending(
        id: UUID,
        slot: StubSlot?,
        name: String?,
        color: StubColorPrimary?,
        pattern: String?,
        surface: String?,
        formality: Int?,
        warmth: Int?
    ) async throws -> StubGarment {
        guard let slot else { throw CameraPersistError.slotRequired }
        let uid = userId
        return try await performThrowingValue { context in
            let pendingFD = FetchDescriptor<PendingCaptureEntity>(predicate: #Predicate { $0.id == id })
            guard let pending = try context.fetch(pendingFD).first,
                  pending.reviewStateRaw == "PENDING",
                  pending.garmentId == nil
            else {
                throw CameraPersistError.pendingUnavailable
            }

            let garmentFD = FetchDescriptor<GarmentEntity>(predicate: #Predicate { $0.id == id })
            if try context.fetch(garmentFD).first != nil {
                throw CameraPersistError.pendingUnavailable
            }

            let userPath = UserGarmentPhotoStore.userPhotoPath(for: id)
            guard UserGarmentPhotoStore.resolvedFileURL(pending.masterURI) != nil
                    || UserGarmentPhotoStore.resolvedFileURL(userPath) != nil
            else {
                throw CameraPersistError.saveFailed
            }

            let garment = CameraPendingCommitBuilder.garment(
                id: id,
                slot: slot,
                name: name,
                imagePath: userPath,
                color: color,
                pattern: pattern,
                surface: surface,
                formality: formality,
                warmth: warmth
            )
            let entity = StubEntityMapper.makeEntity(from: garment, userId: uid)
            entity.captureId = id
            entity.captureSourceRaw = "CAMERA"
            context.insert(entity)
            GarmentIndexSync.upsert(entity: entity, in: context)
            context.insert(
                GarmentImageEntity(
                    userId: uid,
                    originalURI: userPath,
                    isPrimary: true,
                    garment: entity
                )
            )

            let batchId = pending.batchId
            context.delete(pending)
            try Self.deleteBatchIfUnused(batchId, userId: uid, in: context)
            try context.save()
            return garment
        }
    }

    static func applyAbandonCameraPending(
        id: UUID,
        userId: UUID,
        in context: ModelContext
    ) throws -> PhotoCleanup {
        let pendingFD = FetchDescriptor<PendingCaptureEntity>(predicate: #Predicate { $0.id == id })
        if let pending = try context.fetch(pendingFD).first {
            if pending.reviewStateRaw == "COMMITTED" || pending.garmentId != nil {
                return .empty
            }
            var imagePaths = [pending.masterURI]
            if let processed = pending.processedURI { imagePaths.append(processed) }
            if let thumb = pending.thumbnailURI { imagePaths.append(thumb) }
            let batchId = pending.batchId
            context.delete(pending)
            try deleteBatchIfUnused(batchId, userId: userId, in: context)
            return PhotoCleanup(
                garmentIds: [id],
                imagePaths: imagePaths,
                referencedByOthers: []
            )
        }

        let garmentFD = FetchDescriptor<GarmentEntity>(predicate: #Predicate { $0.id == id })
        if try context.fetch(garmentFD).first != nil {
            return .empty
        }
        return PhotoCleanup(
            garmentIds: [id],
            imagePaths: [UserGarmentPhotoStore.pendingPhotoPath(for: id)],
            referencedByOthers: []
        )
    }

    static func applyDiscardInFlightPendings(
        userId: UUID,
        in context: ModelContext
    ) throws -> PhotoCleanup {
        let uid = userId
        let pendingAll = try context.fetch(FetchDescriptor<PendingCaptureEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        var imagePaths: [String] = []
        var ids: [UUID] = []
        var batchIds = Set<UUID>()
        for capture in pendingAll where capture.reviewStateRaw == "PENDING" && capture.garmentId == nil {
            ids.append(capture.id)
            imagePaths.append(capture.masterURI)
            if let processed = capture.processedURI { imagePaths.append(processed) }
            if let thumb = capture.thumbnailURI { imagePaths.append(thumb) }
            batchIds.insert(capture.batchId)
            context.delete(capture)
        }
        for batchId in batchIds {
            try deleteBatchIfUnused(batchId, userId: uid, in: context)
        }
        return PhotoCleanup(
            garmentIds: ids,
            imagePaths: imagePaths,
            referencedByOthers: []
        )
    }

    private static func deleteBatchIfUnused(
        _ batchId: UUID,
        userId: UUID,
        in context: ModelContext
    ) throws {
        let uid = userId
        let remaining = try context.fetch(FetchDescriptor<PendingCaptureEntity>(
            predicate: #Predicate { $0.userId == uid && $0.batchId == batchId }
        ))
        guard remaining.isEmpty else { return }
        let batchFD = FetchDescriptor<CaptureBatchEntity>(predicate: #Predicate { $0.id == batchId })
        for batch in try context.fetch(batchFD) {
            context.delete(batch)
        }
    }
}
