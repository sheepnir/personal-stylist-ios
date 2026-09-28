import Foundation

/// Sprint 9 garment reference crop (#120, ADR-0004). Uses the same staged D-74 commit as
/// Change photo, so `imagePath` and the primary `originalURI` stay one representation and the
/// current photo stays live until the replacement is fully written and committed.
extension LoopDemoModel {
    /// `editSource` is the app-held source bytes the crop was made from; they are kept as-is
    /// (never re-encoded) beside the new displayed file for later re-crops.
    @discardableResult
    func cropGarmentPhoto(garmentId: UUID, croppedJPEG: Data, editSource: Data) async throws -> StubGarment {
        let store = persistence
        let stagingId: UUID
        do {
            stagingId = try await store.stagePhotoReplace(garmentId: garmentId, jpegData: croppedJPEG)
        } catch {
            throw PhotoReplacePersistError.map(error)
        }
        do {
            try UserGarmentPhotoStore.writeSource(editSource, forPhotoId: stagingId)
        } catch {
            try? await store.abandonPhotoReplace(stagingId: stagingId)
            UserGarmentPhotoStore.removeSource(forPhotoId: stagingId)
            throw PhotoReplacePersistError.map(error)
        }
        do {
            let garment = try await store.replaceGarmentPhoto(garmentId: garmentId, stagingId: stagingId)
            applyReplacedPhoto(garment)
            recordDiagnostic("Garment photo cropped")
            return garment
        } catch {
            // Abandon removes the staged file and its source unless a garment references it.
            try? await store.abandonPhotoReplace(stagingId: stagingId)
            throw PhotoReplacePersistError.map(error)
        }
    }
}
