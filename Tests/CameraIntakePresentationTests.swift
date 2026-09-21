import XCTest
import UIKit
@testable import PersonalStylist

/// #270 — native Use Photo must serialize dismiss → persist → payload preview.
/// Disposable 1×1 JPEGs only. Does not claim physical camera proof.
final class CameraIntakePresentationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "CameraIntakePresentationTests.\(UUID().uuidString)"
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

    // MARK: - Native Use Photo callback (UIImagePickerController)

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
    func testCoordinatorMissingImageFiresOnCancel() {
        var received = false
        var cancelled = false
        let coordinator = SystemCameraPicker.Coordinator(
            onImage: { _ in received = true },
            onCancel: { cancelled = true }
        )
        coordinator.imagePickerController(
            UIImagePickerController(),
            didFinishPickingMediaWithInfo: [:]
        )
        XCTAssertFalse(received)
        XCTAssertTrue(cancelled)
    }

    // MARK: - Coordinator drives presentation (not reducer-only)

    @MainActor
    func testCoordinatorUsePhotoDrivesPreviewThenDetails() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let image = Self.makeTinyImage()
        let harness = Harness()

        harness.apply(.startCapture)
        XCTAssertEqual(harness.state.cover, Optional(CameraIntakeCover.capture))
        XCTAssertTrue(harness.state.cover?.isRenderable == true)

        harness.finishPicking(image)
        XCTAssertTrue(harness.didReceiveImage)
        XCTAssertFalse(harness.didCancel)
        XCTAssertNil(harness.state.cover, "native Use Photo dismisses only")
        XCTAssertTrue(harness.state.incomingImage === image, "payload stays through dismiss")
        XCTAssertTrue(harness.effects.isEmpty, "persist waits for coverDismissed")

        harness.apply(.coverDismissed)
        XCTAssertEqual(harness.effects, [.persistIncomingImage])
        XCTAssertNil(harness.state.cover, "no cover without an image payload")
        XCTAssertTrue(harness.state.incomingImage === image)

        await harness.persist(using: model)
        guard case .preview(let payload) = harness.state.cover else {
            return XCTFail("persistSucceeded must present a payload preview")
        }
        XCTAssertTrue(payload.image === image)
        XCTAssertEqual(payload.pending.id, harness.state.pending?.id)
        XCTAssertNil(harness.state.incomingImage, "incomingImage cleared after success")
        XCTAssertTrue(harness.state.cover?.isRenderable == true)
        XCTAssertNil(harness.state.details)

        harness.apply(.previewUsePhoto)
        XCTAssertNil(harness.state.cover)
        XCTAssertNil(harness.state.details, "details wait for coverDismissed")
        XCTAssertEqual(harness.state.queuedDetails?.id, payload.pending.id)

        harness.apply(.coverDismissed)
        XCTAssertEqual(harness.state.details?.id, payload.pending.id)
        XCTAssertNil(harness.state.cover)

        let garments = await store.fetchGarments()
        XCTAssertTrue(garments.isEmpty, "preview Use photo is not a commit")
        await model.abandonCameraPending(id: payload.pending.id)
    }

    @MainActor
    func testCoordinatorCancelWritesNoGarment() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let harness = Harness()

        harness.apply(.startCapture)
        harness.finishCancelling()
        XCTAssertTrue(harness.didCancel)
        XCTAssertFalse(harness.didReceiveImage)
        XCTAssertNil(harness.state.cover)
        XCTAssertNil(harness.state.incomingImage)
        XCTAssertNil(harness.state.details)

        let garments = await store.fetchGarments()
        XCTAssertTrue(garments.isEmpty)
        XCTAssertTrue(model.garments.isEmpty)
    }

    // MARK: - Serialization / reducer

    @MainActor
    func testNativeUsePhotoDoesNotPresentPreviewSameTurn() {
        let image = Self.makeTinyImage()
        var state = CameraIntakeState()
        state.cover = .capture
        state.incomingImage = image
        let effects = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        XCTAssertNil(state.cover)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertNil(state.cover?.previewPayload)
        XCTAssertTrue(state.incomingImage === image)
    }

    @MainActor
    func testPersistSucceededWithoutImageAlertsAndAbandons() {
        var state = CameraIntakeState()
        state.sessionID = 1
        state.persistSessionID = 1
        state.incomingImage = nil
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:missing")
        let effects = CameraIntakePresentation.reduce(&state, .persistSucceeded(pending))
        XCTAssertNil(state.cover)
        XCTAssertEqual(state.alert, Optional(CameraIntakeAlert.persist(CameraIntakeCopy.captureFailed)))
        XCTAssertEqual(effects, [.abandonPending(pending.id)])
        XCTAssertNil(state.details)
    }

    @MainActor
    func testImmediatePersistSucceededPresentsPreviewWithImage() {
        let image = Self.makeTinyImage()
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:ok")
        var state = CameraIntakeState()
        state.cover = .capture
        state.incomingImage = image
        _ = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        let persist = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertEqual(persist, [.persistIncomingImage])
        XCTAssertNil(state.cover)
        let after = CameraIntakePresentation.reduce(&state, .persistSucceeded(pending))
        XCTAssertTrue(after.isEmpty)
        XCTAssertEqual(state.cover?.previewPayload?.pending, pending)
        XCTAssertTrue(state.cover?.previewPayload?.image === image)
        XCTAssertNil(state.incomingImage)
        XCTAssertNil(state.alert)
    }

    @MainActor
    func testPersistFailedShowsRootAlertAndClearsIncoming() {
        var state = CameraIntakeState()
        state.sessionID = 1
        state.persistSessionID = 1
        state.incomingImage = Self.makeTinyImage()
        state.cover = .capture
        let effects = CameraIntakePresentation.reduce(
            &state,
            .persistFailed(CameraIntakeCopy.lowStorage)
        )
        XCTAssertTrue(effects.isEmpty)
        XCTAssertNil(state.cover)
        XCTAssertNil(state.incomingImage)
        XCTAssertNil(state.details)
        XCTAssertEqual(state.alert, Optional(CameraIntakeAlert.persist(CameraIntakeCopy.lowStorage)))
    }

    @MainActor
    func testLateCoverDismissAfterPersistKeepsPreview() {
        let image = Self.makeTinyImage()
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:stale-dismiss")
        var state = CameraIntakeState()
        state.cover = .capture
        state.incomingImage = image
        _ = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        _ = CameraIntakePresentation.reduce(&state, .persistSucceeded(pending))
        XCTAssertNotNil(state.cover?.previewPayload)
        let late = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertTrue(late.isEmpty)
        XCTAssertEqual(state.cover?.previewPayload?.pending, pending)
        XCTAssertTrue(state.cover?.previewPayload?.image === image)
        XCTAssertNil(state.details)
    }

    @MainActor
    func testPreviewUsePhotoSetsDetailsOnlyAfterDismiss() {
        let image = Self.makeTinyImage()
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:details")
        var state = CameraIntakeState()
        state.pending = pending
        state.cover = .preview(CameraPreviewPayload(pending: pending, image: image))
        _ = CameraIntakePresentation.reduce(&state, .previewUsePhoto)
        XCTAssertNil(state.cover)
        XCTAssertNil(state.details)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertEqual(state.details, pending)
        XCTAssertNil(state.cover)
    }

    @MainActor
    func testPreviewCancelAndNativeCancelAbandonWithoutCover() {
        let image = Self.makeTinyImage()
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:cancel")
        var state = CameraIntakeState()
        state.pending = pending
        state.incomingImage = image
        state.cover = .preview(CameraPreviewPayload(pending: pending, image: image))
        let cancel = CameraIntakePresentation.reduce(&state, .previewCancel)
        XCTAssertEqual(cancel, [.abandonPending(pending.id)])
        XCTAssertNil(state.cover)
        XCTAssertNil(state.pending)
        XCTAssertNil(state.incomingImage)
        XCTAssertNil(state.details)

        state.cover = .capture
        state.incomingImage = image
        let native = CameraIntakePresentation.reduce(&state, .nativeCancel)
        XCTAssertTrue(native.isEmpty)
        XCTAssertNil(state.cover)
        XCTAssertNil(state.incomingImage)
    }

    @MainActor
    func testPreviewRetakeQueuesCaptureAfterDismiss() {
        let image = Self.makeTinyImage()
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:retake")
        var state = CameraIntakeState()
        state.pending = pending
        state.cover = .preview(CameraPreviewPayload(pending: pending, image: image))
        let effects = CameraIntakePresentation.reduce(&state, .previewRetake)
        XCTAssertEqual(effects, [.abandonPending(pending.id)])
        XCTAssertNil(state.cover)
        XCTAssertEqual(state.queuedCover, Optional(CameraIntakeCover.capture))
        XCTAssertNil(state.pending)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertEqual(state.cover, Optional(CameraIntakeCover.capture))
        XCTAssertNil(state.queuedCover)
    }

    @MainActor
    func testRepeatedRetakeThenCancelStaysSerialized() {
        let first = Self.makeTinyImage()
        let second = Self.makeTinyImage()
        let firstPending = CameraPending(id: UUID(), imagePath: "pending-photo:one")
        let secondPending = CameraPending(id: UUID(), imagePath: "pending-photo:two")
        var state = CameraIntakeState()

        _ = CameraIntakePresentation.reduce(&state, .startCapture)
        state.incomingImage = first
        _ = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        _ = CameraIntakePresentation.reduce(&state, .persistSucceeded(firstPending))
        _ = CameraIntakePresentation.reduce(&state, .previewRetake)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertEqual(state.cover, Optional(CameraIntakeCover.capture))

        state.incomingImage = second
        _ = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        _ = CameraIntakePresentation.reduce(&state, .persistSucceeded(secondPending))
        XCTAssertEqual(state.cover?.previewPayload?.pending, secondPending)
        XCTAssertTrue(state.cover?.previewPayload?.image === second)

        let cancel = CameraIntakePresentation.reduce(&state, .previewCancel)
        XCTAssertEqual(cancel, [.abandonPending(secondPending.id)])
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertNil(state.cover)
        XCTAssertNil(state.details)
        XCTAssertNil(state.pending)
    }

    @MainActor
    func testLatePersistAfterCancelAbandonsAndDoesNotResurrect() {
        let image = Self.makeTinyImage()
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:late")
        var state = CameraIntakeState()
        _ = CameraIntakePresentation.reduce(&state, .startCapture)
        state.incomingImage = image
        _ = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        XCTAssertEqual(state.persistSessionID, state.sessionID)

        let cancel = CameraIntakePresentation.reduce(&state, .previewCancel)
        XCTAssertTrue(cancel.isEmpty)
        XCTAssertNil(state.incomingImage)

        let late = CameraIntakePresentation.reduce(&state, .persistSucceeded(pending))
        XCTAssertEqual(late, [.abandonPending(pending.id)])
        XCTAssertNil(state.cover)
        XCTAssertNil(state.details)
        XCTAssertNil(state.pending)
        XCTAssertNil(state.alert)
    }

    @MainActor
    func testLatePersistFailedAfterResetDoesNotAlert() {
        var state = CameraIntakeState()
        _ = CameraIntakePresentation.reduce(&state, .startCapture)
        state.incomingImage = Self.makeTinyImage()
        _ = CameraIntakePresentation.reduce(&state, .nativeUsePhoto)
        _ = CameraIntakePresentation.reduce(&state, .coverDismissed)
        _ = CameraIntakePresentation.reduce(&state, .nativeCancel)
        _ = CameraIntakePresentation.reduce(&state, .persistFailed(CameraIntakeCopy.captureFailed))
        XCTAssertNil(state.alert)
        XCTAssertNil(state.cover)
        XCTAssertNil(state.incomingImage)
    }

    // MARK: - Permission startCapture paths

    @MainActor
    func testAlreadyAuthorizedStartCapturePresentsCamera() {
        XCTAssertEqual(CameraPermissionPolicy.action(for: .authorized), .presentCamera)
        var state = CameraIntakeState()
        let effects = CameraIntakePresentation.reduce(&state, .startCapture)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(state.cover, Optional(CameraIntakeCover.capture))
        XCTAssertNil(state.alert)
    }

    @MainActor
    func testFirstRunGrantThenStartCapturePresentsCamera() {
        XCTAssertEqual(CameraPermissionPolicy.action(for: .notDetermined), .requestAccess)
        var state = CameraIntakeState()
        _ = CameraIntakePresentation.reduce(&state, .permissionFallback(.denied))
        XCTAssertNotNil(state.alert)
        let effects = CameraIntakePresentation.reduce(&state, .startCapture)
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(state.cover, Optional(CameraIntakeCover.capture))
        XCTAssertNil(state.alert, "grant path clears a prior fallback")
    }

    @MainActor
    func testPermissionFallbackIsRootAlertNotCover() {
        var state = CameraIntakeState()
        _ = CameraIntakePresentation.reduce(&state, .permissionFallback(.denied))
        XCTAssertEqual(state.alert, Optional(CameraIntakeAlert.permission(.denied)))
        XCTAssertNil(state.cover)
        XCTAssertTrue(state.alert?.showsOpenSettings == true)
        _ = CameraIntakePresentation.reduce(&state, .clearAlert)
        XCTAssertNil(state.alert)
    }

    // MARK: - Persist memory / failure

    @MainActor
    func testPersistThrowClearsIncomingAndWritesNoGarment() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let image = Self.makeTinyImage()
        let harness = Harness()
        harness.apply(.startCapture)
        harness.finishPicking(image)
        harness.apply(.coverDismissed)

        CameraPersistHooks.failAfterPendingFileWrite = CameraPersistError.lowStorage
        await harness.persist(using: model)

        XCTAssertNil(harness.state.cover)
        XCTAssertNil(harness.state.details)
        XCTAssertNil(harness.state.incomingImage)
        XCTAssertEqual(harness.state.alert, Optional(CameraIntakeAlert.persist(CameraIntakeCopy.lowStorage)))
        let garments = await store.fetchGarments()
        XCTAssertTrue(garments.isEmpty)
        XCTAssertTrue(model.garments.isEmpty)
    }

    @MainActor
    func testPreviewCancelAfterSuccessfulPersistWritesNoGarment() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        let image = Self.makeTinyImage()
        let harness = Harness()
        harness.apply(.startCapture)
        harness.finishPicking(image)
        harness.apply(.coverDismissed)
        await harness.persist(using: model)
        guard let id = harness.state.pending?.id else {
            return XCTFail("expected pending after persist")
        }

        harness.apply(.previewCancel)
        XCTAssertEqual(harness.effects, [.abandonPending(id)])
        await model.abandonCameraPending(id: id)

        let garments = await store.fetchGarments()
        XCTAssertTrue(garments.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL("pending-photo:\(id.uuidString)"))
    }

    func testCoverCasesAreNeverEmpty() {
        let pending = CameraPending(id: UUID(), imagePath: "pending-photo:render")
        let preview = CameraIntakeCover.preview(
            CameraPreviewPayload(pending: pending, image: Self.makeTinyImage())
        )
        XCTAssertTrue(CameraIntakeCover.capture.isRenderable)
        XCTAssertTrue(preview.isRenderable)
        XCTAssertNotNil(preview.previewPayload?.image)
    }

    func testSimulatorCameraUnavailableDoesNotFailCI() throws {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw XCTSkip("Simulator camera unavailable. Physical camera is UNVERIFIED_PHONE.")
        }
        let picker = SystemCameraPicker(onImage: { _ in }, onCancel: {})
        XCTAssertNotNil(picker.makeCoordinator())
    }

    // MARK: - Harness (same Coordinator callback the view uses)

    @MainActor
    private final class Harness {
        var state = CameraIntakeState()
        var effects: [CameraIntakeEffect] = []
        var didReceiveImage = false
        var didCancel = false

        private lazy var coordinator = SystemCameraPicker.Coordinator(
            onImage: { [weak self] image in
                guard let self else { return }
                self.didReceiveImage = true
                self.state.incomingImage = image
                self.effects = CameraIntakePresentation.reduce(&self.state, .nativeUsePhoto)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                self.didCancel = true
                self.effects = CameraIntakePresentation.reduce(&self.state, .nativeCancel)
            }
        )

        func apply(_ event: CameraIntakeEvent) {
            effects = CameraIntakePresentation.reduce(&state, event)
        }

        func finishPicking(_ image: UIImage) {
            coordinator.imagePickerController(
                UIImagePickerController(),
                didFinishPickingMediaWithInfo: [.originalImage: image]
            )
        }

        func finishCancelling() {
            coordinator.imagePickerControllerDidCancel(UIImagePickerController())
        }

        func persist(using model: LoopDemoModel) async {
            let event = await CameraIntakePresentation.persistEvent(image: state.incomingImage) { data in
                try await model.beginCameraPending(jpegData: data)
            }
            apply(event)
        }
    }

    private static func makeTinyImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
