import Foundation
import SwiftData

extension SwiftDataPersistenceStore {
    func stagePhotoReplace(garmentId: UUID, jpegData: Data) async throws -> UUID {
        await PhotoReplacePersistHooks.awaitInjectedDelay()
        let exists = await fetchGarments().contains { $0.id == garmentId }
        guard exists else { throw PhotoReplacePersistError.garmentUnavailable }

        let stagingId = UUID()
        let path: String
        do {
            path = try UserGarmentPhotoStore.persistReplaceJPEG(from: jpegData, stagingId: stagingId)
        } catch {
            throw PhotoReplacePersistError.map(error)
        }
        PhotoReplacePersistHooks.lastStagedPath = path
        if let injected = PhotoReplacePersistHooks.failAfterStagingFileWrite {
            PhotoReplacePersistHooks.failAfterStagingFileWrite = nil
            UserGarmentPhotoStore.removeFile(imagePath: path)
            UserGarmentPhotoStore.removeFiles(forGarmentId: stagingId)
            throw PhotoReplacePersistError.map(injected)
        }
        return stagingId
    }

    func abandonPhotoReplace(stagingId: UUID) async throws {
        try await PhotoReplaceGate.shared.run {
            await self.abandonPhotoReplaceUnlocked(stagingId: stagingId)
        }
    }

    func replaceGarmentPhoto(garmentId: UUID, stagingId: UUID) async throws -> StubGarment {
        try await PhotoReplaceGate.shared.run {
            try await self.replaceGarmentPhotoUnlocked(garmentId: garmentId, stagingId: stagingId)
        }
    }

    private func abandonPhotoReplaceUnlocked(stagingId: UUID) async {
        let replacePath = UserGarmentPhotoStore.replacePhotoPath(for: stagingId)
        let userPath = UserGarmentPhotoStore.userPhotoPath(for: stagingId)
        let referenced = await fetchGarments().contains {
            $0.imagePath == replacePath || $0.imagePath == userPath
        }
        guard !referenced else { return }
        UserGarmentPhotoStore.removeFile(imagePath: replacePath)
        UserGarmentPhotoStore.removeFiles(forGarmentId: stagingId)
    }

    private func replaceGarmentPhotoUnlocked(garmentId: UUID, stagingId: UUID) async throws -> StubGarment {
        await PhotoReplacePersistHooks.awaitInjectedDelay()
        let stagedPath = UserGarmentPhotoStore.replacePhotoPath(for: stagingId)
        let newPath = UserGarmentPhotoStore.userPhotoPath(for: stagingId)
        guard UserGarmentPhotoStore.resolvedFileURL(stagedPath) != nil
                || UserGarmentPhotoStore.resolvedFileURL(newPath) != nil
        else {
            throw PhotoReplacePersistError.saveFailed
        }
        if let injected = PhotoReplacePersistHooks.failBeforeMetadataCommit {
            PhotoReplacePersistHooks.failBeforeMetadataCommit = nil
            await abandonPhotoReplaceUnlocked(stagingId: stagingId)
            throw PhotoReplacePersistError.map(injected)
        }

        let uid = userId
        let targetId = garmentId
        do {
            let (garment, cleanup) = try await performThrowingValue { context -> (StubGarment, PhotoCleanup) in
                let garmentFD = FetchDescriptor<GarmentEntity>(predicate: #Predicate { $0.id == targetId })
                guard let entity = try context.fetch(garmentFD).first else {
                    throw PhotoReplacePersistError.garmentUnavailable
                }

                if entity.imagePath == newPath {
                    return (StubEntityMapper.stub(from: entity), .empty)
                }

                var oldPaths = [entity.imagePath].compactMap { $0 }
                oldPaths.append(contentsOf: entity.images.flatMap { img in
                    [img.originalURI, img.processedURI].compactMap { $0 }
                })

                let allGarments = try context.fetch(FetchDescriptor<GarmentEntity>(
                    predicate: #Predicate { $0.userId == uid }
                ))
                var referencedByOthers = Set<String>()
                for other in allGarments where other.id != targetId {
                    if let path = other.imagePath { referencedByOthers.insert(path) }
                    for img in other.images {
                        referencedByOthers.insert(img.originalURI)
                        if let processed = img.processedURI { referencedByOthers.insert(processed) }
                    }
                }
                referencedByOthers.insert(newPath)
                referencedByOthers.insert(stagedPath)

                entity.imagePath = newPath
                entity.updatedAt = Date()
                if let primary = entity.images.first(where: { $0.isPrimary }) ?? entity.images.first {
                    primary.originalURI = newPath
                    primary.processedURI = nil
                    primary.isPrimary = true
                    primary.imageRevision += 1
                } else {
                    context.insert(
                        GarmentImageEntity(
                            userId: uid,
                            originalURI: newPath,
                            isPrimary: true,
                            garment: entity
                        )
                    )
                }
                try context.save()

                return (
                    StubEntityMapper.stub(from: entity),
                    PhotoCleanup(
                        garmentIds: [targetId],
                        imagePaths: oldPaths,
                        referencedByOthers: referencedByOthers
                    )
                )
            }
            cleanup.apply()
            UserGarmentPhotoStore.evictThumbnails()
            return garment
        } catch {
            await abandonPhotoReplaceUnlocked(stagingId: stagingId)
            if error is PhotoReplacePersistError {
                throw error
            }
            throw PhotoReplacePersistError.map(error)
        }
    }
}
