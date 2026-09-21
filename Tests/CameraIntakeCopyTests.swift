import XCTest
import UIKit
@testable import PersonalStylist

/// D-73 / #192 Take photo — copy, permission mapping, cancel/abandon no-write.
/// Disposable generated JPEGs only. Does not claim physical camera proof.
final class CameraIntakeCopyTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "CameraIntakeCopyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Copy

    func testTakePhotoCopyIsExactAndLocal() {
        XCTAssertEqual(CameraIntakeCopy.takePhoto, "Take photo")
        XCTAssertEqual(
            CameraIntakeCopy.takePhotoSubtitle,
            "Photograph a garment. The photo stays on this iPhone."
        )
        XCTAssertEqual(
            CameraIntakeCopy.cameraUsageDescription,
            "To photograph a garment. The photo stays on this iPhone for your wardrobe."
        )
        XCTAssertEqual(CameraIntakeCopy.retake, "Retake")
        XCTAssertEqual(CameraIntakeCopy.usePhoto, "Use photo")
        XCTAssertEqual(CameraIntakeCopy.cancel, "Cancel")
        XCTAssertEqual(CameraIntakeCopy.openSettings, "Open Settings")
        XCTAssertEqual(CameraIntakeCopy.nameAndCategory, "Name and category")
        XCTAssertEqual(CameraIntakeCopy.selectSlot, "Select…")
        XCTAssertEqual(CameraIntakeCopy.untitledWithoutSlot, "Untitled")
        XCTAssertTrue(CameraIntakeCopy.takePhotoSubtitle.contains("stays on this iPhone"))
        XCTAssertTrue(CameraIntakeCopy.deniedMessage.contains("used for the garment locally"))
    }

    func testPreviewAndFailureCopyHaveNoMachineTokens() {
        let joined = CameraIntakeCopy.allUserFacingLines.joined(separator: "\n")
        for forbidden in [
            "HTTP", "http://", "https://", "NSURL", "token",
            "attributeSource", "PendingCapture", "GarmentEntity",
            "beginCameraPending", "NSCameraUsageDescription",
            "TOP", "BOTTOM", "READY", "DRAFT",
        ] {
            XCTAssertFalse(joined.contains(forbidden), "copy must not contain \(forbidden)")
        }
    }

    func testFallbackCopyMapsDeniedRestrictedUnavailable() {
        XCTAssertEqual(
            CameraIntakeCopy.fallbackTitle(for: .denied),
            CameraIntakeCopy.deniedTitle
        )
        XCTAssertEqual(
            CameraIntakeCopy.fallbackMessage(for: .denied),
            CameraIntakeCopy.deniedMessage
        )
        XCTAssertEqual(
            CameraIntakeCopy.fallbackTitle(for: .restricted),
            CameraIntakeCopy.unavailableTitle
        )
        XCTAssertEqual(
            CameraIntakeCopy.fallbackMessage(for: .restricted),
            CameraIntakeCopy.restrictedMessage
        )
        XCTAssertEqual(
            CameraIntakeCopy.fallbackTitle(for: .unavailable),
            CameraIntakeCopy.unavailableTitle
        )
        XCTAssertEqual(
            CameraIntakeCopy.fallbackMessage(for: .unavailable),
            CameraIntakeCopy.unavailableMessage
        )
        XCTAssertTrue(CameraPermissionPolicy.showsOpenSettings(for: .denied))
        XCTAssertTrue(CameraPermissionPolicy.showsOpenSettings(for: .restricted))
        XCTAssertFalse(CameraPermissionPolicy.showsOpenSettings(for: .unavailable))
    }

    func testPersistFailureMapsLowStorageWithoutURLs() {
        let space = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertEqual(CameraIntakeCopy.persistFailure(from: space), CameraIntakeCopy.lowStorage)
        XCTAssertEqual(
            CameraIntakeCopy.persistFailure(from: CameraPersistError.lowStorage),
            CameraIntakeCopy.lowStorage
        )
        XCTAssertEqual(
            CameraIntakeCopy.persistFailure(from: CameraPersistError.saveFailed),
            CameraIntakeCopy.captureFailed
        )
        XCTAssertFalse(CameraIntakeCopy.lowStorage.contains("http"))
        XCTAssertFalse(CameraIntakeCopy.interrupted.contains("URL"))
        XCTAssertFalse(CameraIntakeCopy.saveFailed.contains("Error"))
    }

    func testCameraIntakeModePlacesNameAndCategoryFirst() {
        XCTAssertEqual(
            GarmentEditCopy.identitySectionHeader(mode: .cameraIntake),
            GarmentEditCopy.nameAndCategory
        )
        XCTAssertEqual(GarmentEditCopy.primarySaveTitle(mode: .cameraIntake), GarmentEditCopy.save)
        XCTAssertTrue(FinishDetailsDraft.placesNameAndCategoryFirst(mode: .cameraIntake))
        XCTAssertTrue(FinishDetailsDraft.requiresExplicitSlot(mode: .cameraIntake))
        XCTAssertFalse(FinishDetailsDraft.requiresExplicitSlot(mode: .finishDetails))
        XCTAssertFalse(FinishDetailsDraft.showsNextDraftQueue(mode: .cameraIntake))
        XCTAssertTrue(FinishDetailsDraft.dismissesAfterSuccessfulSave(mode: .cameraIntake))
    }

    // MARK: - Permission mapping

    func testPermissionStateMapping() {
        XCTAssertEqual(
            CameraPermissionPolicy.resolvedState(authorization: .notDetermined, cameraAvailable: true),
            .notDetermined
        )
        XCTAssertEqual(
            CameraPermissionPolicy.resolvedState(authorization: .authorized, cameraAvailable: true),
            .authorized
        )
        XCTAssertEqual(
            CameraPermissionPolicy.resolvedState(authorization: .denied, cameraAvailable: true),
            .denied
        )
        XCTAssertEqual(
            CameraPermissionPolicy.resolvedState(authorization: .restricted, cameraAvailable: true),
            .restricted
        )
        XCTAssertEqual(
            CameraPermissionPolicy.resolvedState(authorization: .authorized, cameraAvailable: false),
            .unavailable
        )
        XCTAssertEqual(
            CameraPermissionPolicy.resolvedState(authorization: .notDetermined, cameraAvailable: false),
            .unavailable
        )

        XCTAssertEqual(CameraPermissionPolicy.action(for: .notDetermined), .requestAccess)
        XCTAssertEqual(CameraPermissionPolicy.action(for: .authorized), .presentCamera)
        XCTAssertEqual(CameraPermissionPolicy.action(for: .denied), .offerSettingsOrFallback)
        XCTAssertEqual(CameraPermissionPolicy.action(for: .restricted), .offerSettingsOrFallback)
        XCTAssertEqual(CameraPermissionPolicy.action(for: .unavailable), .offerSettingsOrFallback)
    }

    // MARK: - Slot + abandon helpers

    func testCameraIntakeDoesNotDefaultSlotToTop() {
        XCTAssertNil(CameraIntakeDraft.defaultSlotForCameraIntake())
        XCTAssertFalse(CameraIntakeDraft.isSlotChosen(nil))
        XCTAssertFalse(CameraIntakeDraft.canPersist(slot: nil))
        XCTAssertTrue(CameraIntakeDraft.canPersist(slot: .bottom))
        XCTAssertEqual(
            CameraIntakeDraft.liveDisplayName(name: "", slot: nil),
            CameraIntakeCopy.untitledWithoutSlot
        )
        XCTAssertEqual(
            CameraIntakeDraft.liveDisplayName(name: "", slot: .bottom),
            StubGarment.untitledName(for: .bottom)
        )
        XCTAssertNotEqual(
            CameraIntakeDraft.liveDisplayName(name: "", slot: nil),
            StubGarment.untitledName(for: .top)
        )
    }

    func testCancelRetakeAbandonHelpersWriteNoGarment() {
        XCTAssertFalse(CameraIntakeDraft.abandonWritesGarment())
        XCTAssertFalse(CameraIntakeDraft.retakeWritesGarment())
        XCTAssertFalse(CameraIntakeDraft.previewCancelWritesGarment())
    }

    @MainActor
    func testAbandonAfterBeginWritesNoGarment() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let jpeg = try Self.makeTinyJPEG()

        let pending = try await model.beginCameraPending(jpegData: jpeg)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(pending.imagePath))

        let before = await store.fetchGarments()
        XCTAssertTrue(before.isEmpty)
        XCTAssertFalse(CameraIntakeDraft.abandonWritesGarment())

        await model.abandonCameraPending(id: pending.id)

        let after = await store.fetchGarments()
        XCTAssertTrue(after.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(pending.imagePath))
    }

    @MainActor
    func testRetakeAbandonThenSecondBeginStillWritesNoGarmentUntilCommit() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let jpeg = try Self.makeTinyJPEG()

        let first = try await model.beginCameraPending(jpegData: jpeg)
        await model.abandonCameraPending(id: first.id)
        XCTAssertFalse(CameraIntakeDraft.retakeWritesGarment())

        let second = try await model.beginCameraPending(jpegData: jpeg)
        let mid = await store.fetchGarments()
        XCTAssertTrue(mid.isEmpty)

        await model.abandonCameraPending(id: second.id)
        let after = await store.fetchGarments()
        XCTAssertTrue(after.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(first.imagePath))
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(second.imagePath))
    }

    @MainActor
    func testCommitRequiresExplicitSlotAndKeepsChosenBottom() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let jpeg = try Self.makeTinyJPEG()
        let pending = try await model.beginCameraPending(jpegData: jpeg)

        XCTAssertFalse(CameraIntakeDraft.canPersist(slot: nil))
        let emptyBefore = model.garments
        XCTAssertTrue(emptyBefore.isEmpty)

        let ok = await model.commitCameraPending(
            id: pending.id,
            fields: CameraIntakeCommitFields(
                slot: .bottom,
                displayName: "Canvas trousers",
                displayNameIsUserSet: true,
                color: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
                pattern: "SOLID",
                surface: "RUGGED",
                formality: 2,
                warmth: 3,
                purchasePrice: nil,
                purchaseCurrency: nil,
                purchaseDate: nil,
                priorWearBucket: nil,
                markReady: true
            )
        )
        XCTAssertTrue(ok)
        let committed = model.garments
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed.first?.slot, .bottom)
        XCTAssertNotEqual(committed.first?.slot, .top)
        XCTAssertEqual(committed.first?.displayName, "Canvas trousers")

        let stored = await store.fetchGarments()
        XCTAssertEqual(stored.map(\.slot), [.bottom])
        XCTAssertEqual(stored.count, 1)

        await model.abandonCameraPending(id: pending.id)
        let afterAbandon = await store.fetchGarments()
        XCTAssertEqual(afterAbandon.count, 1, "abandon after commit must not delete the saved garment")
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(pending.imagePath))
        UserGarmentPhotoStore.removeFiles(forGarmentId: pending.id)
    }

    @MainActor
    func testLoopDemoAbandonLeavesStoreUnchanged() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let jpeg = try Self.makeTinyJPEG()
        let pending = try await model.beginCameraPending(jpegData: jpeg)
        let before = model.garments
        XCTAssertTrue(before.isEmpty)

        await model.abandonCameraPending(id: pending.id)

        let after = model.garments
        XCTAssertTrue(after.isEmpty)
        let stored = await store.fetchGarments()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(pending.imagePath))
    }

    /// 1×1 JPEG — not a personal photo.
    private static func makeTinyJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "CameraIntakeCopyTests", code: 1)
        }
        return data
    }
}
