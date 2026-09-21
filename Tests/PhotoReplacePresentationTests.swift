import XCTest
import UIKit
import PhotosUI
@testable import PersonalStylist

/// #278 — Photos / native Use Photo must serialize dismiss → persist → payload preview → Save.
/// Disposable 1×1 JPEGs only. Does not claim physical camera or limited-library proof.
final class PhotoReplacePresentationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "PhotoReplacePresentationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        PhotoReplacePersistHooks.reset()
    }

    override func tearDownWithError() throws {
        PhotoReplacePersistHooks.reset()
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testCoordinatorUsePhotoFiresOnImageNotCancel() {
        let image = Self.makeTinyImage()
        var received: UIImage?
        var cancelled = false
        let coordinator = SystemCameraPicker.Coordinator(
            onImage: { received = $0 },
            onCancel: { cancelled = true }
        )
        coordinator.imagePickerController(
            UIImagePickerController(),
            didFinishPickingMediaWithInfo: [.originalImage: image]
        )
        XCTAssertTrue(received === image)
        XCTAssertFalse(cancelled)
    }

    @MainActor
    func testLibraryCoordinatorDecodesItemProvider() async throws {
        let image = Self.makeTinyImage()
        var received: UIImage?
        var cancelled = false
        let coordinator = PhotoReplaceLibraryPicker.Coordinator(
            onImage: { received = $0 },
            onCancel: { cancelled = true }
        )
        coordinator.finishPicking(itemProviders: [NSItemProvider(object: image)])
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, received == nil, cancelled == false {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(received)
        XCTAssertFalse(cancelled)
    }

    @MainActor
    func testLibraryCoordinatorEmptyResultsCancel() {
        var received = false
        var cancelled = false
        let coordinator = PhotoReplaceLibraryPicker.Coordinator(
            onImage: { _ in received = true },
            onCancel: { cancelled = true }
        )
        coordinator.picker(PHPickerViewController(configuration: PHPickerConfiguration()), didFinishPicking: [])
        XCTAssertFalse(received)
        XCTAssertTrue(cancelled)
    }

    @MainActor
    func testPhotosPickDrivesPreviewThenSave() async throws {
        let (store, model, garment, original) = try await seededHarnessModel()
        let image = Self.makeTinyImage()
        let harness = Harness()

        harness.apply(.chooseSource(.photos, garmentId: garment.id))
        XCTAssertEqual(harness.state.cover, Optional(PhotoReplaceCover.photos))
        XCTAssertTrue(harness.state.cover?.isRenderable == true)

        await harness.finishPicking(image)
        XCTAssertTrue(harness.didReceiveImage)
        XCTAssertNil(harness.state.cover, "picker dismisses only")
        let decoded = try XCTUnwrap(harness.state.incomingImage, "NSItemProvider decode must yield a UIImage")
        XCTAssertFalse(decoded.size.width.isZero)
        XCTAssertTrue(harness.effects.isEmpty, "persist waits for coverDismissed")

        harness.apply(.coverDismissed)
        XCTAssertEqual(harness.effects, [.persistIncomingImage])
        XCTAssertNil(harness.state.cover, "no cover without an image payload")

        await harness.persist(using: model)
        guard case .preview(let payload) = harness.state.cover else {
            return XCTFail("persistSucceeded must present a payload preview")
        }
        XCTAssertFalse(payload.image.size.width.isZero)
        XCTAssertEqual(payload.pending.garmentId, garment.id)
        XCTAssertNil(harness.state.incomingImage)
        XCTAssertTrue(harness.state.cover?.isRenderable == true)

        let midGarments = await store.fetchGarments()
        let mid = try XCTUnwrap(midGarments.first)
        XCTAssertEqual(mid.imagePath, original, "Save is the only persist point")

        harness.apply(.previewSave)
        XCTAssertNil(harness.state.cover)
        XCTAssertEqual(harness.state.queuedCommit?.id, payload.pending.id)

        harness.apply(.coverDismissed)
        XCTAssertEqual(harness.effects, [.commitPending(payload.pending)])

        await harness.commit(using: model)
        let savedGarments = await store.fetchGarments()
        let stored = try XCTUnwrap(savedGarments.first)
        XCTAssertEqual(stored.id, garment.id)
        XCTAssertNotEqual(stored.imagePath, original)
        XCTAssertEqual(stored.displayName, garment.displayName)
        UserGarmentPhotoStore.removeFile(imagePath: stored.imagePath)
    }

    @MainActor
    func testCameraUsePhotoDrivesPreviewThenCancelWritesNoChange() async throws {
        let (store, model, garment, original) = try await seededHarnessModel()
        let image = Self.makeTinyImage()
        let harness = Harness()

        harness.apply(.chooseSource(.camera, garmentId: garment.id))
        XCTAssertEqual(harness.state.cover, Optional(PhotoReplaceCover.capture))
        await harness.finishPicking(image)
        harness.apply(.coverDismissed)
        await harness.persist(using: model)
        guard case .preview = harness.state.cover else {
            return XCTFail("expected preview")
        }

        harness.apply(.previewCancel)
        XCTAssertNil(harness.state.cover)
        XCTAssertNil(harness.state.pending)
        let cancelledGarments = await store.fetchGarments()
        let stored = try XCTUnwrap(cancelledGarments.first)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertEqual(stored.id, garment.id)
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    @MainActor
    func testNativeUsePhotoDoesNotPresentPreviewSameTurn() {
        let image = Self.makeTinyImage()
        var state = PhotoReplaceState()
        state.cover = .photos
        state.incomingImage = image
        let effects = PhotoReplacePresentation.reduce(&state, .nativeUsePhoto)
        XCTAssertNil(state.cover)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertTrue(state.incomingImage === image)
    }

    @MainActor
    func testLatePersistAfterCancelAbandons() async throws {
        let (_, model, garment, original) = try await seededHarnessModel()
        var state = PhotoReplaceState()
        _ = PhotoReplacePresentation.reduce(&state, .chooseSource(.photos, garmentId: garment.id))
        state.incomingImage = Self.makeTinyImage()
        _ = PhotoReplacePresentation.reduce(&state, .nativeUsePhoto)
        _ = PhotoReplacePresentation.reduce(&state, .coverDismissed)
        XCTAssertEqual(state.persistSessionID, state.sessionID)
        _ = PhotoReplacePresentation.reduce(&state, .nativeCancel)

        let event = await PhotoReplacePresentation.persistEvent(
            image: Self.makeTinyImage(),
            garmentId: garment.id
        ) { garmentId, data in
            try await model.beginPhotoReplace(garmentId: garmentId, jpegData: data)
        }
        let effects = PhotoReplacePresentation.reduce(&state, event)
        if case .persistSucceeded(let pending) = event {
            XCTAssertEqual(effects, [.abandonPending(pending.id)])
            await model.abandonPhotoReplace(stagingId: pending.id)
        } else {
            XCTFail("expected persistSucceeded for a valid image")
        }
        XCTAssertNil(state.cover?.previewPayload)
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    @MainActor
    func testChooseAnotherRequeuesLastSource() {
        var state = PhotoReplaceState()
        let garmentId = UUID()
        _ = PhotoReplacePresentation.reduce(&state, .chooseSource(.photos, garmentId: garmentId))
        let pending = PhotoReplacePending(
            id: UUID(),
            garmentId: garmentId,
            imagePath: "replace-photo:\(UUID().uuidString)"
        )
        state.pending = pending
        state.cover = .preview(PhotoReplacePreviewPayload(pending: pending, image: Self.makeTinyImage()))
        let effects = PhotoReplacePresentation.reduce(&state, .previewChooseAnother)
        XCTAssertEqual(effects, [.abandonPending(pending.id)])
        XCTAssertNil(state.cover)
        XCTAssertEqual(state.queuedCover, Optional(PhotoReplaceCover.photos))
    }

    @MainActor
    func testPersistSucceededWithoutImageAlertsAndAbandons() {
        var state = PhotoReplaceState()
        state.sessionID = 1
        state.persistSessionID = 1
        state.incomingImage = nil
        let pending = PhotoReplacePending(
            id: UUID(),
            garmentId: UUID(),
            imagePath: "replace-photo:missing"
        )
        let effects = PhotoReplacePresentation.reduce(&state, .persistSucceeded(pending))
        XCTAssertNil(state.cover)
        XCTAssertEqual(state.alert, Optional(PhotoReplaceAlert.persist(PhotoReplaceCopy.captureFailed)))
        XCTAssertEqual(effects, [.abandonPending(pending.id)])
    }

    @MainActor
    func testCoverDismissedDuringCommitDoesNotAbandon() {
        var state = PhotoReplaceState()
        let pending = PhotoReplacePending(
            id: UUID(),
            garmentId: UUID(),
            imagePath: "replace-photo:\(UUID().uuidString)"
        )
        state.pending = pending
        state.commitInFlight = true
        state.cover = nil
        let effects = PhotoReplacePresentation.reduce(&state, .coverDismissed)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(state.pending, pending)
        XCTAssertTrue(state.commitInFlight)
    }

    @MainActor
    func testChooseSourceIgnoredWhileCommitInFlight() {
        var state = PhotoReplaceState()
        let garmentId = UUID()
        _ = PhotoReplacePresentation.reduce(&state, .chooseSource(.photos, garmentId: garmentId))
        state.commitInFlight = true
        state.sessionID = 4
        let effects = PhotoReplacePresentation.reduce(&state, .chooseSource(.camera, garmentId: garmentId))
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(state.sessionID, 4)
        XCTAssertEqual(state.lastSource, Optional(PhotoReplaceSource.photos))
        XCTAssertTrue(state.commitInFlight)
    }

    @MainActor
    func testPermissionFallbackDoesNotMutateGarment() async throws {
        let (store, _, garment, original) = try await seededHarnessModel()
        var state = PhotoReplaceState()
        _ = PhotoReplacePresentation.reduce(&state, .permissionFallback(.denied))
        XCTAssertEqual(state.alert, Optional(PhotoReplaceAlert.permission(.denied)))
        XCTAssertNil(state.cover)
        let deniedGarments = await store.fetchGarments()
        let stored = try XCTUnwrap(deniedGarments.first)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertEqual(stored.id, garment.id)
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    // MARK: - Helpers

    @MainActor
    private func seededHarnessModel() async throws -> (
        InMemoryPersistenceStore,
        LoopDemoModel,
        StubGarment,
        String
    ) {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = StubGarment(
            id: UUID(),
            displayName: "Harness Shirt",
            slot: .top,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: nil, name: nil),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 2,
            warmth: 2,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(),
            displayNameSource: "USER"
        )
        let original = try UserGarmentPhotoStore.persistJPEG(
            from: Self.makeTinyJPEG(),
            garmentId: garment.id
        )
        garment.imagePath = original
        try await store.saveGarment(garment)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.bindPhotoReplaceStore(store)
        return (store, model, garment, original)
    }

    private static func makeTinyImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private static func makeTinyJPEG() throws -> Data {
        guard let data = makeTinyImage().jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "PhotoReplacePresentationTests", code: 1)
        }
        return data
    }
}

@MainActor
private final class Harness {
    var state = PhotoReplaceState()
    var effects: [PhotoReplaceEffect] = []
    var didReceiveImage = false
    var didCancel = false

    func apply(_ event: PhotoReplaceEvent) {
        effects = PhotoReplacePresentation.reduce(&state, event)
    }

    func finishPicking(_ image: UIImage) async {
        let coordinator = PhotoReplaceLibraryPicker.Coordinator(
            onImage: { [weak self] picked in
                self?.didReceiveImage = true
                self?.state.incomingImage = picked
                self?.apply(.nativeUsePhoto)
            },
            onCancel: { [weak self] in
                self?.didCancel = true
                self?.apply(.nativeCancel)
            }
        )
        coordinator.finishPicking(itemProviders: [NSItemProvider(object: image)])
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, !didReceiveImage, !didCancel {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func persist(using model: LoopDemoModel) async {
        let event = await PhotoReplacePresentation.persistEvent(
            image: state.incomingImage,
            garmentId: state.garmentId
        ) { garmentId, data in
            try await model.beginPhotoReplace(garmentId: garmentId, jpegData: data)
        }
        apply(event)
    }

    func commit(using model: LoopDemoModel) async {
        guard case .commitPending(let pending) = effects.first else { return }
        let ok = await model.commitPhotoReplace(garmentId: pending.garmentId, stagingId: pending.id)
        apply(ok ? .commitSucceeded : .commitFailed(PhotoReplaceCopy.saveFailed))
    }
}
