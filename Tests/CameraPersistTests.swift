import XCTest
import SwiftData
import UIKit
@testable import PersonalStylist

/// D-73 camera persistence — disposable JPEG + temp SwiftData only. No real wardrobe data.
final class CameraPersistTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "CameraPersistTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        CameraPersistHooks.reset()
    }

    override func tearDownWithError() throws {
        CameraPersistHooks.reset()
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - begin → abandon

    @MainActor
    func testBeginAbandonLeavesNoGarmentOrFileAndRelaunchIsEmpty() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        let jpeg = try Self.makeTinyJPEG()
        let id = try await store.beginCameraPending(jpegData: jpeg)

        let inspect = ModelContext(first)
        let pending = try XCTUnwrap(try inspect.fetch(FetchDescriptor<PendingCaptureEntity>()).first { $0.id == id })
        XCTAssertEqual(pending.reviewStateRaw, "PENDING")
        XCTAssertEqual(pending.analysisStateRaw, "NOT_REQUESTED")
        XCTAssertNil(pending.garmentId)
        XCTAssertNil(pending.slotIntentRaw)
        XCTAssertNil(pending.proposalJSON)
        XCTAssertTrue(pending.masterURI.hasPrefix(UserGarmentPhotoStore.pendingPathPrefix))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(pending.masterURI))
        let beforeAbandon = await store.fetchGarments()
        XCTAssertTrue(beforeAbandon.isEmpty)

        try await store.abandonCameraPending(id: id)
        try await store.abandonCameraPending(id: id)

        let afterAbandonGarments = await store.fetchGarments()
        XCTAssertTrue(afterAbandonGarments.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: id)))
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.userPhotoPath(for: id)))
        let afterAbandon = ModelContext(first)
        XCTAssertTrue(try afterAbandon.fetch(FetchDescriptor<PendingCaptureEntity>()).filter { $0.id == id }.isEmpty)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        let relaunchGarments = await relaunchStore.fetchGarments()
        XCTAssertFalse(relaunchGarments.contains { $0.id == id })
        XCTAssertTrue(try ModelContext(relaunched).fetch(FetchDescriptor<PendingCaptureEntity>()).filter { $0.id == id }.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: id)))
        alive = nil
    }

    // MARK: - begin → commit Bottom

    @MainActor
    func testBeginCommitBottomSurvivesRelaunchOnce() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        let jpeg = try Self.makeTinyJPEG()
        let id = try await store.beginCameraPending(jpegData: jpeg)
        let emptyBeforeCommit = await store.fetchGarments()
        XCTAssertTrue(emptyBeforeCommit.isEmpty)

        let committed = try await store.commitCameraPending(
            id: id,
            slot: .bottom,
            name: "Camera Canvas Pants",
            color: StubColorPrimary(family: "navy", hex: nil, name: nil),
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 2,
            warmth: 2
        )
        XCTAssertEqual(committed.id, id)
        XCTAssertEqual(committed.slot, .bottom)
        XCTAssertEqual(committed.displayName, "Camera Canvas Pants")
        XCTAssertEqual(committed.displayNameSource, "USER")
        XCTAssertEqual(committed.attributeSource["slot"], "USER")
        XCTAssertEqual(committed.attributeSource["color"], "USER")
        XCTAssertEqual(committed.readiness, .ready)
        XCTAssertEqual(committed.imagePath, UserGarmentPhotoStore.userPhotoPath(for: id))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(committed.imagePath))

        let garments = await store.fetchGarments()
        XCTAssertEqual(garments.map(\.id), [id])
        XCTAssertEqual(garments.first?.slot, .bottom)

        let inspect = ModelContext(first)
        XCTAssertTrue(try inspect.fetch(FetchDescriptor<PendingCaptureEntity>()).filter { $0.id == id }.isEmpty)
        let entity = try XCTUnwrap(try inspect.fetch(FetchDescriptor<GarmentEntity>()).first { $0.id == id })
        XCTAssertEqual(entity.captureSourceRaw, "CAMERA")
        XCTAssertEqual(entity.slotRaw, StubSlot.bottom.rawValue)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        let relaunchedGarments = await relaunchStore.fetchGarments()
        XCTAssertEqual(relaunchedGarments.map(\.id), [id])
        XCTAssertEqual(relaunchedGarments.first?.slot, .bottom)
        XCTAssertEqual(relaunchedGarments.first?.displayName, "Camera Canvas Pants")
        XCTAssertEqual(relaunchedGarments.first?.imagePath, UserGarmentPhotoStore.userPhotoPath(for: id))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(relaunchedGarments.first?.imagePath))
        XCTAssertEqual(relaunchedGarments.count, 1)

        do {
            _ = try await relaunchStore.commitCameraPending(
                id: id,
                slot: .bottom,
                name: "Duplicate Pants",
                color: nil,
                pattern: nil,
                surface: nil,
                formality: nil,
                warmth: nil
            )
            XCTFail("second commit must not resurrect a duplicate")
        } catch CameraPersistError.pendingUnavailable {
            // expected
        }
        let afterSecondCommit = await relaunchStore.fetchGarments()
        XCTAssertEqual(afterSecondCommit.count, 1)
        alive = nil
    }

    func testCommitWithoutSlotRejected() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let id = try await store.beginCameraPending(jpegData: try Self.makeTinyJPEG())
        do {
            _ = try await store.commitCameraPending(
                id: id,
                slot: nil,
                name: "Should Not Save",
                color: nil,
                pattern: nil,
                surface: nil,
                formality: nil,
                warmth: nil
            )
            XCTFail("nil slot must be rejected")
        } catch CameraPersistError.slotRequired {
            // expected
        }
        let rejected = await store.fetchGarments()
        XCTAssertTrue(rejected.isEmpty)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: id)))
        try await store.abandonCameraPending(id: id)
    }

    func testCommitAfterAbandonDeleteClearResetFails() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let jpeg = try Self.makeTinyJPEG()

        let abandoned = try await store.beginCameraPending(jpegData: jpeg)
        try await store.abandonCameraPending(id: abandoned)
        await assertCommitUnavailable(store, id: abandoned)
        let afterAbandon = await store.fetchGarments()
        XCTAssertTrue(afterAbandon.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: abandoned)))

        let deleted = try await store.beginCameraPending(jpegData: jpeg)
        _ = try await store.commitCameraPending(
            id: deleted,
            slot: .jacket,
            name: "Camera Field Jacket",
            color: nil,
            pattern: nil,
            surface: nil,
            formality: nil,
            warmth: nil
        )
        try await store.deleteGarment(id: deleted)
        await assertCommitUnavailable(store, id: deleted)
        let afterDelete = await store.fetchGarments()
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.userPhotoPath(for: deleted)))

        let cleared = try await store.beginCameraPending(jpegData: jpeg)
        try await store.clearWardrobeAndLooks()
        await assertCommitUnavailable(store, id: cleared)
        let afterClear = await store.fetchGarments()
        XCTAssertTrue(afterClear.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: cleared)))

        let resetId = try await store.beginCameraPending(jpegData: jpeg)
        _ = try await store.resetActiveStyleProfile()
        await assertCommitUnavailable(store, id: resetId)
        let afterReset = await store.fetchGarments()
        XCTAssertTrue(afterReset.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: resetId)))
    }

    @MainActor
    func testClearAndResetDeletePendingFiles() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        let jpeg = try Self.makeTinyJPEG()

        let clearId = try await store.beginCameraPending(jpegData: jpeg)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: clearId)))
        try await store.clearWardrobeAndLooks()
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: clearId)))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<PendingCaptureEntity>()).isEmpty)
        await assertCommitUnavailable(store, id: clearId)

        let resetId = try await store.beginCameraPending(jpegData: jpeg)
        _ = try await store.resetActiveStyleProfile()
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.pendingPhotoPath(for: resetId)))
        await assertCommitUnavailable(store, id: resetId)
    }

    func testUndecodableAndPostWriteFailureLeaveNoOrphan() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        do {
            _ = try await store.beginCameraPending(jpegData: Data([0x00, 0x01, 0x02]))
            XCTFail("garbage bytes must not persist")
        } catch CameraPersistError.undecodableImage {
            // expected
        }
        let afterBadBytes = await store.fetchGarments()
        XCTAssertTrue(afterBadBytes.isEmpty)

        CameraPersistHooks.failAfterPendingFileWrite = CameraPersistError.saveFailed
        do {
            _ = try await store.beginCameraPending(jpegData: try Self.makeTinyJPEG())
            XCTFail("injected row failure must throw")
        } catch CameraPersistError.saveFailed {
            // expected
        }
        let leftover = CameraPersistHooks.lastPendingFilePath
        XCTAssertNotNil(leftover)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(leftover))
        let afterHookFail = await store.fetchGarments()
        XCTAssertTrue(afterHookFail.isEmpty)
    }

    func testPartialCommitStaysDraftNeverInventedReady() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let id = try await store.beginCameraPending(jpegData: try Self.makeTinyJPEG())
        let draft = try await store.commitCameraPending(
            id: id,
            slot: .footwear,
            name: nil,
            color: nil,
            pattern: nil,
            surface: nil,
            formality: nil,
            warmth: nil
        )
        XCTAssertEqual(draft.slot, .footwear)
        XCTAssertEqual(draft.displayName, StubGarment.untitledName(for: .footwear))
        XCTAssertEqual(draft.displayNameSource, "DERIVED")
        XCTAssertEqual(draft.readiness, .draft)
        XCTAssertNil(draft.colorPrimary)
        XCTAssertNil(draft.pattern)
        XCTAssertEqual(draft.attributeSource["slot"], "USER")
        XCTAssertNil(draft.attributeSource["color"])
        try await store.abandonCameraPending(id: id)
        UserGarmentPhotoStore.removeFiles(forGarmentId: id)
    }

    func testCameraAuthorizationProbeStates() {
        XCTAssertEqual(
            CameraAuthorization.status(using: CameraAuthorization.Probe(
                authorizationStatus: { _ in .authorized },
                cameraAvailable: { false }
            )),
            .unavailable
        )
        XCTAssertEqual(
            CameraAuthorization.status(using: CameraAuthorization.Probe(
                authorizationStatus: { _ in .authorized },
                cameraAvailable: { true }
            )),
            .authorized
        )
        XCTAssertEqual(
            CameraAuthorization.status(using: CameraAuthorization.Probe(
                authorizationStatus: { _ in .denied },
                cameraAvailable: { true }
            )),
            .denied
        )
        XCTAssertEqual(
            CameraAuthorization.status(using: CameraAuthorization.Probe(
                authorizationStatus: { _ in .restricted },
                cameraAvailable: { true }
            )),
            .restricted
        )
        XCTAssertEqual(
            CameraAuthorization.status(using: CameraAuthorization.Probe(
                authorizationStatus: { _ in .notDetermined },
                cameraAvailable: { true }
            )),
            .notDetermined
        )
    }

    // MARK: - Helpers

    private func assertCommitUnavailable(_ store: PersistenceStore, id: UUID) async {
        do {
            _ = try await store.commitCameraPending(
                id: id,
                slot: .bottom,
                name: "Should Not Resurrect",
                color: nil,
                pattern: nil,
                surface: nil,
                formality: nil,
                warmth: nil
            )
            XCTFail("late commit must fail for \(id)")
        } catch CameraPersistError.pendingUnavailable {
            // expected
        } catch {
            XCTFail("expected pendingUnavailable, got \(error)")
        }
    }

    private static func makeTinyJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "CameraPersistTests", code: 1)
        }
        return data
    }
}
