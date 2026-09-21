import Foundation

/// Weak-to-strong store binding so this extension can persist without editing `LoopDemoModel.swift`.
enum PhotoReplaceStoreBinding {
    private static let map = NSMapTable<AnyObject, Box>.weakToStrongObjects()

    private final class Box {
        let store: PersistenceStore
        init(_ store: PersistenceStore) { self.store = store }
    }

    static func bind(_ model: LoopDemoModel, store: PersistenceStore) {
        map.setObject(Box(store), forKey: model)
    }

    static func store(for model: LoopDemoModel) -> PersistenceStore? {
        map.object(forKey: model)?.store
    }
}

extension LoopDemoModel {
    func bindPhotoReplaceStore(_ store: PersistenceStore) {
        PhotoReplaceStoreBinding.bind(self, store: store)
    }

    /// D-74 — stage a replacement JPEG under a new id. Original garment unchanged.
    func beginPhotoReplace(garmentId: UUID, jpegData: Data) async throws -> PhotoReplacePending {
        let store = try requirePhotoReplaceStore()
        let stagingId = try await store.stagePhotoReplace(garmentId: garmentId, jpegData: jpegData)
        return PhotoReplacePending(
            id: stagingId,
            garmentId: garmentId,
            imagePath: UserGarmentPhotoStore.replacePhotoPath(for: stagingId)
        )
    }

    /// D-74 — drop the staged file. Writes no garment mutation. Idempotent.
    func abandonPhotoReplace(stagingId: UUID) async {
        try? await PhotoReplaceStoreBinding.store(for: self)?.abandonPhotoReplace(stagingId: stagingId)
    }

    /// D-74 — switch metadata to the staged file, then delete the previous owned unshared file.
    @discardableResult
    func commitPhotoReplace(garmentId: UUID, stagingId: UUID) async -> Bool {
        do {
            let store = try requirePhotoReplaceStore()
            let garment = try await store.replaceGarmentPhoto(garmentId: garmentId, stagingId: stagingId)
            applyReplacedPhoto(garment)
            return true
        } catch {
            try? await PhotoReplaceStoreBinding.store(for: self)?.abandonPhotoReplace(stagingId: stagingId)
            recordDiagnostic("Couldn’t replace garment photo")
            return false
        }
    }

    func applyReplacedPhoto(_ garment: StubGarment) {
        UserGarmentPhotoStore.evictThumbnails()
        if let idx = garments.firstIndex(where: { $0.id == garment.id }) {
            garments[idx] = garment
        }
        if selectedGarment?.id == garment.id {
            selectedGarment = garment
        }
        showToast(PhotoReplaceCopy.saved)
        recordDiagnostic("Photo replaced — \(garment.displayName)")
    }

    private func requirePhotoReplaceStore() throws -> PersistenceStore {
        guard let store = PhotoReplaceStoreBinding.store(for: self) else {
            throw PhotoReplacePersistError.garmentUnavailable
        }
        return store
    }
}
