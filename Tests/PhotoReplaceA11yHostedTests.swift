import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// #280 hosted photo-replace chrome. XCTest windows see UIKit preview buttons
/// (labels / hints / identifiers). Physical VoiceOver is UNVERIFIED_PHONE.
@MainActor
final class PhotoReplaceA11yHostedTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var window: UIWindow?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "PhotoReplaceA11yHostedTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    func testPreviewActionsExposeDistinctHintsOnSESizedWindowAtAX5() throws {
        let image = makeTinyImage()
        _ = try render(
            PhotoReplacePreview(
                image: image,
                onChooseAnother: {},
                onSave: {},
                onCancel: {}
            )
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            size: CGSize(width: 375, height: 667)
        )

        let save = try XCTUnwrap(button(identifier: "photo.replace.save"))
        XCTAssertEqual(save.accessibilityLabel, PhotoReplaceCopy.save)
        XCTAssertEqual(save.accessibilityHint, PhotoReplaceCopy.saveHint)
        XCTAssertGreaterThanOrEqual(save.bounds.height, 44)

        let another = try XCTUnwrap(button(identifier: "photo.replace.chooseAnother"))
        XCTAssertEqual(another.accessibilityLabel, PhotoReplaceCopy.chooseAnother)
        XCTAssertEqual(another.accessibilityHint, PhotoReplaceCopy.chooseAnotherHint)
        XCTAssertGreaterThanOrEqual(another.bounds.height, 44)

        let footerCancel = try XCTUnwrap(button(identifier: "photo.replace.cancel"))
        XCTAssertEqual(footerCancel.accessibilityLabel, PhotoReplaceCopy.cancel)
        XCTAssertEqual(footerCancel.accessibilityHint, PhotoReplaceCopy.previewFooterCancelHint)
        XCTAssertGreaterThanOrEqual(footerCancel.bounds.height, 44)

        let navCancel = try XCTUnwrap(barButton(identifier: "photo.replace.cancel.nav"))
        XCTAssertEqual(navCancel.accessibilityLabel, PhotoReplaceCopy.cancel)
        XCTAssertEqual(navCancel.accessibilityHint, PhotoReplaceCopy.previewNavCancelHint)
        XCTAssertNotEqual(navCancel.accessibilityHint, footerCancel.accessibilityHint)
    }

    func testReviewChangePhotoRendersOnSESizedWindowAtAX5() async throws {
        let garment = disposableGarment(name: "Canvas Tee")
        let store = InMemoryPersistenceStore(garments: [garment], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.selectedGarment = garment

        let image = try render(
            NavigationStack {
                ReviewCardView(model: model, onBuild: {})
            }
            .environment(\.persistenceStore, store)
            .environment(\.dynamicTypeSize, .accessibility5),
            size: CGSize(width: 375, height: 667)
        )
        XCTAssertTrue(isNonBlank(image), "AX5 SE garment detail must paint Change photo chrome")
        XCTAssertTrue(
            navTitles().contains("Canvas Tee") || visibleTexts().contains(PhotoReplaceCopy.changePhoto),
            "Detail must show the garment or Change photo. Titles: \(navTitles()) texts: \(visibleTexts())"
        )
    }

    func testAlertMessageUsesPersistFailureHumanCopy() {
        let alert = PhotoReplaceAlert.persist(
            PhotoReplaceCopy.persistFailure(from: PhotoReplacePersistError.lowStorage)
        )
        XCTAssertEqual(alert.message, PhotoReplaceCopy.lowStorage)
        XCTAssertEqual(alert.title, "Couldn’t use that photo")
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(alert.message))
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(alert.title))
    }

    // MARK: - Host

    @discardableResult
    private func render<V: View>(_ root: V, size: CGSize) throws -> UIImage {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        let host = UIHostingController(rootView: root)
        let hosted = UIWindow(frame: CGRect(origin: .zero, size: size))
        hosted.rootViewController = host
        hosted.makeKeyAndVisible()
        host.view.frame = hosted.bounds
        host.view.layoutIfNeeded()
        hosted.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let image = UIGraphicsImageRenderer(size: hosted.bounds.size).image { _ in
            host.view.drawHierarchy(in: hosted.bounds, afterScreenUpdates: true)
        }
        window = hosted
        return image
    }

    private func button(identifier: String) -> UIButton? {
        var found: UIButton?
        func visit(_ view: UIView) {
            if view.accessibilityIdentifier == identifier, let button = view as? UIButton {
                found = button
            }
            for sub in view.subviews { visit(sub) }
        }
        if let window { visit(window) }
        return found
    }

    private func barButton(identifier: String) -> UIBarButtonItem? {
        var found: UIBarButtonItem?
        func visit(_ view: UIView) {
            if let nav = view as? UINavigationBar {
                for item in nav.items ?? [] {
                    for barItem in (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? []) {
                        if barItem.accessibilityIdentifier == identifier {
                            found = barItem
                        }
                    }
                }
            }
            for sub in view.subviews { visit(sub) }
        }
        if let window { visit(window) }
        return found
    }

    private func navTitles() -> [String] {
        var titles: [String] = []
        func visit(_ view: UIView) {
            if let nav = view as? UINavigationBar {
                for item in nav.items ?? [] {
                    if let title = item.title { titles.append(title) }
                }
            }
            for sub in view.subviews { visit(sub) }
        }
        if let window { visit(window) }
        return titles
    }

    private func visibleTexts() -> [String] {
        var texts: [String] = []
        func visit(_ view: UIView) {
            if let label = view.accessibilityLabel, !label.isEmpty { texts.append(label) }
            if let button = view as? UIButton, let title = button.currentTitle { texts.append(title) }
            if let label = view as? UILabel, let text = label.text { texts.append(text) }
            for sub in view.subviews { visit(sub) }
        }
        if let window { visit(window) }
        return texts
    }

    private func isNonBlank(_ image: UIImage) -> Bool {
        guard let data = image.cgImage?.dataProvider?.data else { return false }
        return Set(data as Data).count > 10
    }

    private func disposableGarment(name: String) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: .top,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 3,
            warmth: 3,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
    }

    private func makeTinyImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
