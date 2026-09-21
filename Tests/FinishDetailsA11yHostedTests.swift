import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// #280 hosted Finish details chrome. XCTest windows see NavigationStack titles,
/// not SwiftUI identifier/trait nodes (same limit as other unit-hosted SwiftUI).
/// Label / selected / disabled contracts are in `FinishDetailsA11yContractTests`.
/// Keyboard + AX5 Save bar size is already covered by `FinishDetailsSaveBarHostedTests`.
/// Physical VoiceOver is UNVERIFIED_PHONE.
@MainActor
final class FinishDetailsA11yHostedTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var window: UIWindow?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "FinishDetailsA11yHostedTests.\(UUID().uuidString)"
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

    func testFinishSheetRendersOnSESizedWindowAtAX5() async throws {
        let draft = disposableDraft(name: "Canvas Tee", color: nil)
        let model = await loadedModel(garments: [draft])

        let image = try render(
            FinishDetailsSheet(model: model, garmentId: draft.id, mode: .finishDetails, onSaved: {})
                .environment(\.dynamicTypeSize, .accessibility5),
            size: CGSize(width: 375, height: 667)
        )
        XCTAssertTrue(isNonBlank(image), "AX5 SE Finish details must paint chrome")
        XCTAssertTrue(
            navTitles().contains("Canvas Tee") || navTitles().contains("Finish details"),
            "Finish sheet nav title. Seen: \(navTitles())"
        )
    }

    func testSaveBarStaysOnSECanvasWithKeyboardRemainderWhenDisabled() {
        let missingColor = GarmentEditCopy.saveAccessibilityHint(
            canMarkReady: false,
            isSaving: false,
            missingRequiredFields: ["Color"],
            hasRequiredSlot: true
        )
        XCTAssertTrue(missingColor.contains("Color"))

        let size = fit(
            FinishDetailsSaveBar(
                primaryTitle: GarmentEditCopy.save,
                canMarkReady: false,
                canSaveDraft: true,
                isSaving: false,
                remainingDraftCount: 0,
                showsNextDraftQueue: false,
                saveHint: missingColor,
                saveAsDraftHint: GarmentEditCopy.saveDraftHint,
                onSaveReady: {},
                onSaveDraft: {},
                onNextDraft: {}
            )
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            in: CGSize(width: 375, height: 667)
        )
        let remaining = 667 - 260
        XCTAssertGreaterThanOrEqual(size.height, 44)
        XCTAssertLessThanOrEqual(size.height, CGFloat(remaining))
        XCTAssertLessThan(size.height, 667)
    }

    func testCustomColourRowSpeaksNameAndSelected() {
        let custom = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        )
        XCTAssertEqual(custom.accessibilityLabel, "Forest Moss")
        let size = fit(FinishDetailsCustomColorRow(state: custom), in: CGSize(width: 375, height: 667))
        XCTAssertGreaterThanOrEqual(size.height, 44)
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

    private func fit<V: View>(_ view: V, in size: CGSize) -> CGSize {
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.bounds = CGRect(origin: .zero, size: size)
        return host.sizeThatFits(in: size)
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

    private func isNonBlank(_ image: UIImage) -> Bool {
        guard let data = image.cgImage?.dataProvider?.data else { return false }
        return Set(data as Data).count > 10
    }

    private func loadedModel(garments: [StubGarment]) async -> LoopDemoModel {
        let store = InMemoryPersistenceStore(garments: garments, sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        return model
    }

    private func disposableDraft(name: String, color: StubColorPrimary?) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: .top,
            readiness: .draft,
            availability: "AVAILABLE",
            colorPrimary: color,
            pattern: nil,
            surface: nil,
            imagePath: nil,
            formality: nil,
            warmth: nil,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            displayNameSource: "USER"
        )
    }
}
