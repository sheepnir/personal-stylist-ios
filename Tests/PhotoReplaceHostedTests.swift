import XCTest
import SwiftUI
import UIKit
import PhotosUI
@testable import PersonalStylist

/// #278 hosted-view evidence. Waits for real SwiftUI dismiss / visible chrome.
/// Does not call `reduce(.coverDismissed)`. Physical shutter is UNVERIFIED_PHONE.
@MainActor
final class PhotoReplaceHostedTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var rig: PhotoReplaceHostRig?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "PhotoReplaceHostedTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        PhotoReplacePersistHooks.reset()
        PhotoReplaceLibraryPickerHooks.reset()
        SystemCameraPickerHooks.reset()
    }

    override func tearDownWithError() throws {
        if let path = rig?.originalPath {
            UserGarmentPhotoStore.removeFile(imagePath: path)
        }
        if let path = rig?.model.garments.first?.imagePath {
            UserGarmentPhotoStore.removeFile(imagePath: path)
        }
        rig?.teardown()
        rig = nil
        PhotoReplacePersistHooks.reset()
        PhotoReplaceLibraryPickerHooks.reset()
        SystemCameraPickerHooks.reset()
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    func testPhotosPickerShowsVisiblePreviewThenSave() async throws {
        let rig = try await makeRig()
        let original = try XCTUnwrap(rig.originalPath)
        rig.startPhotos()
        try await injectPhotosPick(rig)

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }
        XCTAssertTrue(rig.hasVisiblePreviewControls(), "preview Save / Choose another / Cancel must be on screen")
        rig.assertNoBlankProductCover()
        let beforeSave = await rig.store.fetchGarments()
        XCTAssertEqual(beforeSave.first?.imagePath, original)

        XCTAssertTrue(rig.tapVisible(PhotoReplaceCopy.save))
        // Product contract: Save dismisses the preview first (`.previewSave` clears the cover
        // and raises `commitInFlight`); the commit effect is only issued from the real
        // `fullScreenCover(onDismiss:)` (`.coverDismissed` -> `.commitPending`) and then runs
        // in a Task. The preview controls therefore leave the screen before the store is
        // written, so the wait must also cover `commitInFlight`, which only clears on
        // `.commitSucceeded` / `.commitFailed`.
        try await waitUntil(rig, timeout: 6) {
            !rig.hasVisiblePreviewControls() && !rig.session.state.commitInFlight
        }
        XCTAssertFalse(rig.session.state.commitInFlight, "commit must have completed")
        XCTAssertNil(rig.session.state.alert, "a successful save must not raise a persist alert")
        XCTAssertNil(rig.session.state.cover)
        XCTAssertNil(rig.session.state.pending, "a committed staging handle must be released")
        let savedGarments = await rig.store.fetchGarments()
        let stored = try XCTUnwrap(savedGarments.first)
        XCTAssertEqual(stored.id, rig.garmentId)
        XCTAssertNotEqual(stored.imagePath, original)
        XCTAssertEqual(stored.displayName, "Hosted Shirt")
        XCTAssertEqual(
            rig.model.garments.first(where: { $0.id == rig.garmentId })?.imagePath,
            stored.imagePath,
            "model must reflect the committed photo path"
        )
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()
    }

    func testCameraUsePhotoShowsVisiblePreviewThenCancel() async throws {
        let rig = try await makeRig()
        let original = try XCTUnwrap(rig.originalPath)
        rig.startAuthorizedCapture()
        try await injectNativeUsePhoto(rig)

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }
        XCTAssertTrue(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()

        XCTAssertTrue(rig.tapVisible(PhotoReplaceCopy.cancel))
        try await waitUntil(rig, timeout: 6) { !rig.hasVisiblePreviewControls() }
        let cancelledGarments = await rig.store.fetchGarments()
        let stored = try XCTUnwrap(cancelledGarments.first)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertEqual(stored.id, rig.garmentId)
        rig.assertNoBlankProductCover()
    }

    func testSlowPersistStillShowsPreviewAfterRealDismiss() async throws {
        PhotoReplacePersistHooks.delayNanoseconds = 400_000_000
        let rig = try await makeRig()
        rig.startPhotos()
        try await injectPhotosPick(rig)

        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            rig.pump()
            XCTAssertFalse(rig.hasVisiblePreviewControls(), "preview must wait for persist after dismiss")
            rig.assertNoBlankProductCover()
            try await Task.sleep(for: .milliseconds(40))
        }

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }
        XCTAssertTrue(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()
    }

    func testFailingPersistShowsRootAlertAndLeavesOriginal() async throws {
        PhotoReplacePersistHooks.failAfterStagingFileWrite = PhotoReplacePersistError.lowStorage
        let rig = try await makeRig()
        let original = try XCTUnwrap(rig.originalPath)
        rig.startPhotos()
        try await injectPhotosPick(rig)

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePersistAlert() }
        XCTAssertTrue(rig.hasVisiblePersistAlert())
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        let failedGarments = await rig.store.fetchGarments()
        let stored = try XCTUnwrap(failedGarments.first)
        XCTAssertEqual(stored.imagePath, original)
        rig.assertNoBlankProductCover()
    }

    func testPhotosPickerEmptyResultsUsesProductionCancel() async throws {
        let rig = try await makeRig()
        let original = try XCTUnwrap(rig.originalPath)
        rig.startPhotos()
        try await waitUntil(rig, timeout: 6) { PhotoReplaceLibraryPickerHooks.lastCoordinator != nil }
        let coordinator = try XCTUnwrap(PhotoReplaceLibraryPickerHooks.lastCoordinator)
        coordinator.picker(
            PHPickerViewController(configuration: PHPickerConfiguration()),
            didFinishPicking: []
        )
        try await waitUntil(rig, timeout: 6) { !rig.hasVisiblePhotosCover() || rig.session.state.cover == nil }
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        let stored = await rig.store.fetchGarments()
        XCTAssertEqual(stored.first?.imagePath, original)
        rig.assertNoBlankProductCover()
    }

    func testPreviewControlsMeet44ptOnSEViewport() async throws {
        let created = try await PhotoReplaceHostRig(
            defaults: defaults,
            windowSize: CGSize(width: 320, height: 568)
        )
        rig = created
        created.startPhotos()
        try await injectPhotosPick(created)
        try await waitUntil(created, timeout: 6) { created.hasVisiblePreviewControls() }
        created.assertPreviewButtonsMeetMinimumTarget()
        XCTAssertTrue(created.visibleTexts().contains(PhotoReplaceCopy.save))
        XCTAssertTrue(created.visibleTexts().contains(PhotoReplaceCopy.chooseAnother))
        XCTAssertTrue(created.visibleTexts().contains(PhotoReplaceCopy.cancel))
    }

    func testChooseAnotherReturnsPickerThenCancelLeavesOriginal() async throws {
        let rig = try await makeRig()
        let original = try XCTUnwrap(rig.originalPath)
        rig.startPhotos()
        try await injectPhotosPick(rig)
        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }

        PhotoReplaceLibraryPickerHooks.reset()
        XCTAssertTrue(rig.tapVisible(PhotoReplaceCopy.chooseAnother))
        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePhotosCover() }
        XCTAssertTrue(rig.hasVisiblePhotosCover())
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()

        try await injectPhotosPick(rig)
        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }
        XCTAssertTrue(rig.tapVisible(PhotoReplaceCopy.cancel))
        try await waitUntil(rig, timeout: 6) { !rig.hasVisiblePreviewControls() }
        let afterCancel = await rig.store.fetchGarments()
        let stored = try XCTUnwrap(afterCancel.first)
        XCTAssertEqual(stored.imagePath, original)
        rig.assertNoBlankProductCover()
    }

    // MARK: - Rig

    private func makeRig() async throws -> PhotoReplaceHostRig {
        let created = try await PhotoReplaceHostRig(defaults: defaults)
        rig = created
        return created
    }

    private func injectPhotosPick(_ rig: PhotoReplaceHostRig) async throws {
        try await waitUntil(rig, timeout: 6) { PhotoReplaceLibraryPickerHooks.lastCoordinator != nil }
        let coordinator = try XCTUnwrap(
            PhotoReplaceLibraryPickerHooks.lastCoordinator,
            "production PhotoReplaceLibraryPicker.Coordinator must exist"
        )
        coordinator.finishPicking(itemProviders: [NSItemProvider(object: Self.makeTinyImage())])
        rig.pump()
    }

    private func injectNativeUsePhoto(_ rig: PhotoReplaceHostRig) async throws {
        try await waitUntil(rig, timeout: 6) { SystemCameraPickerHooks.lastCoordinator != nil }
        let coordinator = try XCTUnwrap(
            SystemCameraPickerHooks.lastCoordinator,
            "production SystemCameraPicker.Coordinator must exist"
        )
        coordinator.imagePickerController(
            UIImagePickerController(),
            didFinishPickingMediaWithInfo: [.originalImage: Self.makeTinyImage()]
        )
        rig.pump()
    }

    private func waitUntil(
        _ rig: PhotoReplaceHostRig,
        timeout: TimeInterval,
        _ predicate: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            rig.pump()
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        rig.pump()
        XCTFail("Timed out waiting for hosted replace chrome. Visible: \(rig.visibleTexts()) cover=\(String(describing: rig.session.state.cover))")
    }

    private static func makeTinyImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}

@MainActor
private final class PhotoReplaceHostRig {
    let store: InMemoryPersistenceStore
    let model: LoopDemoModel
    let session: PhotoReplaceSession
    let garmentId: UUID
    let originalPath: String
    let host: UIHostingController<PhotoReplaceHost<HostBackground>>
    let window: UIWindow

    init(defaults: UserDefaults, windowSize: CGSize = CGSize(width: 390, height: 844)) async throws {
        store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = StubGarment(
            id: UUID(),
            displayName: "Hosted Shirt",
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
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "PhotoReplaceHostedTests", code: 1)
        }
        originalPath = try UserGarmentPhotoStore.persistJPEG(from: jpeg, garmentId: garment.id)
        garment.imagePath = originalPath
        garmentId = garment.id
        try await store.saveGarment(garment)
        model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        session = PhotoReplaceSession()
        session.attach(model, store: store)
        let root = PhotoReplaceHost(session: session) {
            HostBackground()
        }
        host = UIHostingController(rootView: root)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    func teardown() {
        window.isHidden = true
        window.rootViewController = nil
    }

    func startPhotos() {
        session.apply(.chooseSource(.photos, garmentId: garmentId))
        pump()
    }

    func startAuthorizedCapture() {
        XCTAssertEqual(CameraPermissionPolicy.action(for: .authorized), .presentCamera)
        session.apply(.chooseSource(.camera, garmentId: garmentId))
        pump()
    }

    func pump() {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window.layoutIfNeeded()
        for controller in presentedControllers() {
            if controller.view.bounds.size == .zero {
                controller.view.frame = window.bounds
            }
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    func hasVisiblePreviewControls() -> Bool {
        let texts = visibleTexts()
        let labels = texts.contains(PhotoReplaceCopy.save)
            && texts.contains(PhotoReplaceCopy.chooseAnother)
            && texts.contains(PhotoReplaceCopy.cancel)
        let identifiers = containsIdentifier("photo.replace.save")
            && containsIdentifier("photo.replace.chooseAnother")
            && containsIdentifier("photo.replace.cancel")
        return labels || identifiers
    }

    func hasVisiblePhotosCover() -> Bool {
        containsIdentifier("photo.replace.photos")
    }

    func hasVisiblePersistAlert() -> Bool {
        if let alert = presentedControllers().compactMap({ $0 as? UIAlertController }).first {
            let title = alert.title ?? ""
            let message = alert.message ?? ""
            return title.contains("Couldn’t use that photo")
                || message.contains(PhotoReplaceCopy.lowStorage)
                || message.contains(PhotoReplaceCopy.captureFailed)
        }
        let texts = visibleTexts()
        return texts.contains(where: { $0.contains("Couldn’t use that photo") })
            && texts.contains(where: {
                $0.contains(PhotoReplaceCopy.lowStorage) || $0.contains(PhotoReplaceCopy.captureFailed)
            })
    }

    func assertPreviewButtonsMeetMinimumTarget() {
        pump()
        for identifier in ["photo.replace.save", "photo.replace.chooseAnother", "photo.replace.cancel"] {
            var found = false
            func check(_ node: UIView) {
                guard node.accessibilityIdentifier == identifier, let button = node as? UIButton else { return }
                found = true
                XCTAssertGreaterThanOrEqual(button.bounds.height, 44, identifier)
                XCTAssertEqual(button.accessibilityLabel, button.currentTitle)
                XCTAssertTrue(button.accessibilityTraits.contains(.button))
            }
            walkView(window, visit: check)
            for controller in presentedControllers() {
                walkView(controller.view, visit: check)
            }
            XCTAssertTrue(found, "missing \(identifier)")
        }
    }

    func tapVisible(_ label: String) -> Bool {
        pump()
        let identifier: String?
        switch label {
        case PhotoReplaceCopy.save: identifier = "photo.replace.save"
        case PhotoReplaceCopy.chooseAnother: identifier = "photo.replace.chooseAnother"
        case PhotoReplaceCopy.cancel: identifier = "photo.replace.cancel"
        default: identifier = nil
        }
        for object in walk(from: window) {
            guard matches(object, label: label, identifier: identifier) else { continue }
            if let control = object as? UIControl {
                control.sendActions(for: .touchUpInside)
                pump()
                return true
            }
            if object.accessibilityActivate() {
                pump()
                return true
            }
        }
        return false
    }

    func assertNoBlankProductCover() {
        for controller in productPresentedControllers() {
            if containsIdentifier(in: controller.view, "photo.replace.preview")
                || containsIdentifier(in: controller.view, "photo.replace.photos")
                || containsIdentifier(in: controller.view, "camera.intake.capture") {
                continue
            }
            let texts = collectTexts(from: controller.view)
            let meaningful = texts.contains(where: {
                $0 == PhotoReplaceCopy.save
                    || $0 == PhotoReplaceCopy.chooseAnother
                    || $0.contains("Couldn’t use that photo")
                    || $0.contains(PhotoReplaceCopy.lowStorage)
            })
            if meaningful { continue }
            if controller is UIAlertController { continue }
            let snapshot = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            if let data = snapshot.cgImage?.dataProvider?.data {
                let unique = Set(data as Data)
                XCTAssertGreaterThan(
                    unique.count,
                    4,
                    "Presented product cover must not be a blank/black full-screen. Texts: \(texts)"
                )
            }
            XCTAssertFalse(
                texts.isEmpty && controller.view.subviews.isEmpty,
                "Presented product cover has no content"
            )
        }
    }

    func visibleTexts() -> [String] {
        var texts: [String] = []
        for root in allRootViews() {
            texts.append(contentsOf: collectTexts(from: root))
        }
        for controller in presentedControllers() {
            if let alert = controller as? UIAlertController {
                if let title = alert.title { texts.append(title) }
                if let message = alert.message { texts.append(message) }
            }
            texts.append(contentsOf: collectTexts(from: controller.view))
        }
        return Array(Set(texts))
    }

    private func allRootViews() -> [UIView] {
        var roots = [window as UIView]
        if let scene = window.windowScene {
            roots.append(contentsOf: scene.windows.map { $0 as UIView })
        }
        return roots
    }

    private func presentedControllers() -> [UIViewController] {
        var result: [UIViewController] = []
        var current = host.presentedViewController
        while let controller = current {
            result.append(controller)
            if let nav = controller as? UINavigationController {
                result.append(contentsOf: nav.viewControllers)
            }
            current = controller.presentedViewController
        }
        return result
    }

    private func productPresentedControllers() -> [UIViewController] {
        presentedControllers().filter {
            !($0 is UIImagePickerController) && !($0 is PHPickerViewController)
        }
    }

    private func containsIdentifier(_ identifier: String) -> Bool {
        containsIdentifier(in: window, identifier)
            || presentedControllers().contains { containsIdentifier(in: $0.view, identifier) }
    }

    private func containsIdentifier(in view: UIView, _ identifier: String) -> Bool {
        var found = false
        walkView(view) { node in
            if node.accessibilityIdentifier == identifier { found = true }
        }
        return found
    }

    private func collectTexts(from view: UIView) -> [String] {
        collectTexts(fromAny: view)
    }

    private func collectTexts(fromAny element: Any) -> [String] {
        var texts: [String] = []
        guard let object = element as? NSObject else { return texts }
        if let label = object.accessibilityLabel, !label.isEmpty { texts.append(label) }
        if let view = object as? UIView {
            if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
                texts.append(identifier)
            }
            if let button = view as? UIButton, let title = button.currentTitle { texts.append(title) }
            if let label = view as? UILabel, let text = label.text { texts.append(text) }
            if let nav = view as? UINavigationBar {
                for item in nav.items ?? [] {
                    if let title = item.title { texts.append(title) }
                    for barItem in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
                        if let title = barItem.title { texts.append(title) }
                        if let label = barItem.accessibilityLabel { texts.append(label) }
                    }
                }
            }
            for sub in view.subviews {
                texts.append(contentsOf: collectTexts(fromAny: sub))
            }
            if let elements = view.accessibilityElements {
                for child in elements { texts.append(contentsOf: collectTexts(fromAny: child)) }
            }
        }
        return texts
    }

    private func matches(_ object: NSObject, label: String, identifier: String?) -> Bool {
        if object.accessibilityLabel == label { return true }
        if let identifier, let view = object as? UIView, view.accessibilityIdentifier == identifier { return true }
        if let button = object as? UIButton, button.currentTitle == label { return true }
        if let text = object as? UILabel, text.text == label { return true }
        return false
    }

    private func walk(from view: UIView) -> [NSObject] {
        var objects: [NSObject] = []
        func visit(_ element: Any) {
            guard let object = element as? NSObject else { return }
            objects.append(object)
            if let nested = object as? UIView {
                for sub in nested.subviews { visit(sub) }
                if let elements = nested.accessibilityElements {
                    for child in elements { visit(child) }
                }
            }
        }
        for root in allRootViews() { visit(root) }
        for controller in presentedControllers() { visit(controller.view) }
        return objects
    }

    private func walkView(_ view: UIView, visit: (UIView) -> Void) {
        visit(view)
        if let elements = view.accessibilityElements {
            for element in elements {
                if let nested = element as? UIView {
                    walkView(nested, visit: visit)
                }
            }
        }
        for sub in view.subviews {
            walkView(sub, visit: visit)
        }
    }
}

private struct HostBackground: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .accessibilityIdentifier("photo.replace.host")
    }
}
