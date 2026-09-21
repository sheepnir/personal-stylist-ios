import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// #270 hosted-view evidence. Waits for real SwiftUI dismiss / visible chrome.
/// Does not call `reduce(.coverDismissed)`. Physical shutter is UNVERIFIED_PHONE.
@MainActor
final class CameraIntakeHostedTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var rig: CameraHostRig?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "CameraIntakeHostedTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        CameraPersistHooks.reset()
        SystemCameraPickerHooks.reset()
    }

    override func tearDownWithError() throws {
        rig?.teardown()
        rig = nil
        CameraPersistHooks.reset()
        SystemCameraPickerHooks.reset()
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    func testCoordinatorUsePhotoShowsVisiblePreviewThenDetails() async throws {
        let rig = makeRig()
        rig.startAuthorizedCapture()
        try await injectNativeUsePhoto(rig)

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }
        XCTAssertTrue(rig.hasVisiblePreviewControls(), "preview Use photo / Retake / Cancel must be on screen")
        rig.assertNoBlankProductCover()

        XCTAssertTrue(rig.tapVisible(CameraIntakeCopy.usePhoto))
        try await waitUntil(rig, timeout: 6) { rig.hasVisibleDetails() }
        XCTAssertTrue(rig.hasVisibleDetails(), "details must show Name and category plus Select… or Slot")
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()
    }

    func testRetakeReturnsCaptureAndCancelWritesNoGarment() async throws {
        let rig = makeRig()
        rig.startAuthorizedCapture()
        try await injectNativeUsePhoto(rig)
        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }

        SystemCameraPickerHooks.reset()
        XCTAssertTrue(rig.tapVisible(CameraIntakeCopy.retake))
        try await waitUntil(rig, timeout: 6) { rig.hasVisibleCaptureCover() }
        XCTAssertTrue(rig.hasVisibleCaptureCover(), "retake must return the capture cover")
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()

        try await injectNativeUsePhoto(rig)
        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }

        XCTAssertTrue(rig.tapVisible(CameraIntakeCopy.cancel))
        try await waitUntil(rig, timeout: 6) {
            !rig.hasVisiblePreviewControls() && !rig.hasVisibleDetails()
        }
        let garments = await rig.store.fetchGarments()
        XCTAssertTrue(garments.isEmpty)
        XCTAssertTrue(rig.model.garments.isEmpty)
        rig.assertNoBlankProductCover()
    }

    func testSlowPersistStillShowsPreviewAfterRealDismiss() async throws {
        CameraPersistHooks.delayNanoseconds = 400_000_000
        let rig = makeRig()
        rig.startAuthorizedCapture()
        try await injectNativeUsePhoto(rig)

        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            rig.pump()
            XCTAssertFalse(rig.hasVisiblePreviewControls(), "preview must wait for persist after dismiss")
            XCTAssertFalse(rig.hasVisibleDetails())
            rig.assertNoBlankProductCover()
            try await Task.sleep(for: .milliseconds(40))
        }

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePreviewControls() }
        XCTAssertTrue(rig.hasVisiblePreviewControls())
        rig.assertNoBlankProductCover()
    }

    func testFailingPersistShowsRootAlertAndNoPreview() async throws {
        CameraPersistHooks.failAfterPendingFileWrite = CameraPersistError.lowStorage
        let rig = makeRig()
        rig.startAuthorizedCapture()
        try await injectNativeUsePhoto(rig)

        try await waitUntil(rig, timeout: 6) { rig.hasVisiblePersistAlert() }
        XCTAssertTrue(rig.hasVisiblePersistAlert(), "root persist alert must be visible")
        XCTAssertTrue(rig.visibleTexts().contains(where: { $0.contains("Couldn’t use that photo") }))
        XCTAssertTrue(
            rig.visibleTexts().contains(where: {
                $0.contains(CameraIntakeCopy.lowStorage) || $0.contains(CameraIntakeCopy.captureFailed)
            })
        )
        XCTAssertFalse(rig.hasVisiblePreviewControls())
        XCTAssertFalse(rig.hasVisibleDetails())
        let garments = await rig.store.fetchGarments()
        XCTAssertTrue(garments.isEmpty)
        rig.assertNoBlankProductCover()
    }

    // MARK: - Rig

    private func makeRig() -> CameraHostRig {
        let created = CameraHostRig(defaults: defaults)
        rig = created
        return created
    }

    private func injectNativeUsePhoto(_ rig: CameraHostRig) async throws {
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
        _ rig: CameraHostRig,
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
        XCTFail("Timed out waiting for hosted camera chrome. Visible: \(rig.visibleTexts()) cover=\(String(describing: rig.session.state.cover))")
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
private final class CameraHostRig {
    let store: InMemoryPersistenceStore
    let model: LoopDemoModel
    let session: CameraIntakeSession
    let host: UIHostingController<CameraIntakeHost<HostBackground>>
    let window: UIWindow

    init(defaults: UserDefaults) {
        store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        model = LoopDemoModel(store: store, preferences: defaults)
        session = CameraIntakeSession()
        session.attach(model)
        let root = CameraIntakeHost(session: session) {
            HostBackground()
        }
        host = UIHostingController(rootView: root)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
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

    func startAuthorizedCapture() {
        XCTAssertEqual(CameraPermissionPolicy.action(for: .authorized), .presentCamera)
        session.apply(.startCapture)
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
        let labels = texts.contains(CameraIntakeCopy.usePhoto)
            && texts.contains(CameraIntakeCopy.retake)
            && texts.contains(CameraIntakeCopy.cancel)
        let identifiers = containsIdentifier("camera.intake.usePhoto")
            && containsIdentifier("camera.intake.retake")
            && containsIdentifier("camera.intake.cancel")
        return labels || identifiers
    }

    func hasVisibleDetails() -> Bool {
        let texts = visibleTexts()
        let hasIdentity = texts.contains(CameraIntakeCopy.nameAndCategory)
            || texts.contains(GarmentEditCopy.nameField)
            || texts.contains("Name")
        let hasSlot = texts.contains(CameraIntakeCopy.selectSlot)
            || texts.contains(CameraIntakeCopy.slotLabel)
        return hasIdentity && hasSlot && !texts.isEmpty
    }

    func hasVisibleCaptureCover() -> Bool {
        containsIdentifier("camera.intake.capture")
            || presentedControllers().contains(where: { $0 is UIImagePickerController })
    }

    func hasVisiblePersistAlert() -> Bool {
        if let alert = presentedControllers().compactMap({ $0 as? UIAlertController }).first {
            let title = alert.title ?? ""
            let message = alert.message ?? ""
            return title.contains("Couldn’t use that photo")
                || message.contains(CameraIntakeCopy.lowStorage)
                || message.contains(CameraIntakeCopy.captureFailed)
        }
        let texts = visibleTexts()
        return texts.contains(where: { $0.contains("Couldn’t use that photo") })
            && texts.contains(where: {
                $0.contains(CameraIntakeCopy.lowStorage) || $0.contains(CameraIntakeCopy.captureFailed)
            })
    }

    func tapVisible(_ label: String) -> Bool {
        pump()
        let identifier: String?
        switch label {
        case CameraIntakeCopy.usePhoto: identifier = "camera.intake.usePhoto"
        case CameraIntakeCopy.retake: identifier = "camera.intake.retake"
        case CameraIntakeCopy.cancel: identifier = "camera.intake.cancel"
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
            if containsIdentifier(in: controller.view, "camera.intake.preview")
                || containsIdentifier(in: controller.view, "camera.intake.capture") {
                continue
            }
            let texts = collectTexts(from: controller.view)
            let meaningful = texts.contains(where: {
                $0 == CameraIntakeCopy.usePhoto
                    || $0 == CameraIntakeCopy.retake
                    || $0 == CameraIntakeCopy.nameAndCategory
                    || $0 == CameraIntakeCopy.selectSlot
                    || $0.contains("Couldn’t use that photo")
                    || $0.contains(CameraIntakeCopy.lowStorage)
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
        presentedControllers().filter { !($0 is UIImagePickerController) }
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
            if let toolbar = view as? UIToolbar {
                for barItem in toolbar.items ?? [] {
                    if let title = barItem.title { texts.append(title) }
                    if let label = barItem.accessibilityLabel { texts.append(label) }
                }
            }
            for sub in view.subviews {
                texts.append(contentsOf: collectTexts(fromAny: sub))
            }
            if let elements = view.accessibilityElements {
                for child in elements { texts.append(contentsOf: collectTexts(fromAny: child)) }
            }
            let count = view.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let child = view.accessibilityElement(at: index) {
                        texts.append(contentsOf: collectTexts(fromAny: child))
                    }
                }
            }
        } else {
            let count = object.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) {
                        texts.append(contentsOf: collectTexts(fromAny: child))
                    }
                }
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
                let count = nested.accessibilityElementCount()
                if count > 0 && count != NSNotFound {
                    for index in 0..<count {
                        if let child = nested.accessibilityElement(at: index) { visit(child) }
                    }
                }
            }
        }
        for root in allRootViews() { visit(root) }
        for controller in presentedControllers() { visit(controller.view) }
        return objects
    }

    private func walkView(_ view: UIView, visit: (UIView) -> Void) {
        visit(view)
        let count = view.accessibilityElementCount()
        if count > 0 && count != NSNotFound {
            for index in 0..<count {
                if let nested = view.accessibilityElement(at: index) as? UIView {
                    walkView(nested, visit: visit)
                }
            }
        }
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
            .accessibilityIdentifier("camera.intake.host")
    }
}
