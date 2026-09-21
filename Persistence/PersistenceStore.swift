import Foundation
import SwiftUI

protocol PersistenceStore: AnyObject, Sendable {
    var backendName: String { get }

    func fetchGarments() async -> [StubGarment]
    func saveGarment(_ garment: StubGarment) async throws
    func fetchOutfits() async -> [StubOutfit]
    func saveOutfit(_ outfit: StubOutfit) async throws
    func fetchWearEvents() async -> [StubWearEvent]
    func fetchWearEvents(on day: Date) async -> [StubWearEvent]
    func fetchWearAggregates() async -> WearAggregates
    func saveWearEvent(_ event: StubWearEvent) async throws
    /// D-72 — mark a wear event voided. Missing or already-voided ids are success no-ops.
    func voidWearEvent(id: UUID) async throws
    func fetchStyleProfile() async -> StubStyleProfile?
    func saveStyleProfile(_ profile: StubStyleProfile) async throws

    /// Bumped on every successful destructive op so late generate/swap saves can be ignored.
    var dataGeneration: Int { get }

    func deleteGarment(id: UUID) async throws
    func clearWardrobeAndLooks() async throws
    func resetActiveStyleProfile() async throws -> StubStyleProfile
    func fetchSets() async -> [StubSet]

    /// D-73 — durable camera file + PendingCapture. No garment and no default slot.
    func beginCameraPending(jpegData: Data) async throws -> UUID
    /// Cancel / retake. Deletes the pending row and owned files. Idempotent.
    func abandonCameraPending(id: UUID) async throws
    /// File + metadata, then one garment with a real slot. Late work after abandon/delete/clear/reset fails.
    func commitCameraPending(
        id: UUID,
        slot: StubSlot?,
        name: String?,
        color: StubColorPrimary?,
        pattern: String?,
        surface: String?,
        formality: Int?,
        warmth: Int?
    ) async throws -> StubGarment

    /// D-74 — stage a replacement JPEG under a new id. Does not mutate the garment.
    func stagePhotoReplace(garmentId: UUID, jpegData: Data) async throws -> UUID
    /// Drop a staged replacement file. Idempotent. Original garment unchanged.
    func abandonPhotoReplace(stagingId: UUID) async throws
    /// Point the existing garment at a staged file, then delete the previous owned unshared file.
    /// Missing / deleted / cleared garments fail closed and do not resurrect.
    func replaceGarmentPhoto(garmentId: UUID, stagingId: UUID) async throws -> StubGarment
}

extension PersistenceStore {
    /// Stage then commit. On commit failure the staged file is abandoned.
    func replaceGarmentPhoto(garmentId: UUID, jpegData: Data) async throws -> StubGarment {
        let stagingId = try await stagePhotoReplace(garmentId: garmentId, jpegData: jpegData)
        do {
            return try await replaceGarmentPhoto(garmentId: garmentId, stagingId: stagingId)
        } catch {
            try? await abandonPhotoReplace(stagingId: stagingId)
            throw error
        }
    }
}

private enum PersistenceStoreKey: EnvironmentKey {
    static let defaultValue: PersistenceStore = InMemoryPersistenceStore.shared
}

extension EnvironmentValues {
    var persistenceStore: PersistenceStore {
        get { self[PersistenceStoreKey.self] }
        set { self[PersistenceStoreKey.self] = newValue }
    }
}
