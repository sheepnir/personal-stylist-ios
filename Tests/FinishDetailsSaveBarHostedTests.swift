import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// #279 Save bar + custom colour layout on an iPhone SE canvas.
/// Measures the same chrome the sheet uses via `UIHostingController.sizeThatFits`.
/// VoiceOver matrix is #280. Physical keyboard / TestFlight remain UNVERIFIED_PHONE.
@MainActor
final class FinishDetailsSaveBarHostedTests: XCTestCase {
    private let seSize = CGSize(width: 375, height: 667)
    private let keyboardHeight: CGFloat = 260

    func testSEViewportKeepsDistinctSaveTargetsAtLeast44pt() {
        let size = fit(saveBar(), in: seSize)
        XCTAssertGreaterThanOrEqual(size.height, 44, "Save bar must meet 44 pt on SE width")
        XCTAssertLessThanOrEqual(size.width, seSize.width)
        XCTAssertLessThan(size.height, seSize.height, "bar must fit the SE canvas")
        XCTAssertEqual(GarmentEditCopy.save, "Save")
        XCTAssertEqual(GarmentEditCopy.saveAsDraft, "Save as draft")
        XCTAssertNotEqual(GarmentEditCopy.save, GarmentEditCopy.saveAsDraft)
    }

    func testCustomColourRowIsSelectedAndSaveStaysReady() {
        let custom = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        )
        XCTAssertTrue(custom.isCustom)
        XCTAssertFalse(FinishDetailsColorDraft.missingColor(custom))
        XCTAssertEqual(custom.accessibilityLabel, "Forest Moss")

        let size = fit(FinishDetailsCustomColorRow(state: custom), in: seSize)
        XCTAssertGreaterThanOrEqual(size.height, 44)
        XCTAssertLessThanOrEqual(size.width, seSize.width)
    }

    func testKeyboardInsetLeavesSaveTargetsVisibleOnSE() {
        let size = fit(saveBar(), in: seSize)
        let remaining = seSize.height - keyboardHeight
        XCTAssertGreaterThanOrEqual(size.height, 44)
        XCTAssertLessThanOrEqual(
            size.height,
            remaining,
            "Save bar (\(size.height)) must remain in the SE canvas above a \(keyboardHeight) pt keyboard"
        )
    }

    func testAX5SESizeCategoryKeepsSaveTargetsReachable() {
        let size = fit(
            saveBar().environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            in: seSize
        )
        XCTAssertGreaterThanOrEqual(size.height, 44, "AX5 Save bar height \(size)")
        XCTAssertLessThanOrEqual(size.width, seSize.width + 0.5, "AX5 bar must stay within SE width")
        XCTAssertLessThan(size.height, seSize.height, "AX5 bar must remain on the SE canvas")
    }

    private func saveBar() -> FinishDetailsSaveBar {
        FinishDetailsSaveBar(
            primaryTitle: GarmentEditCopy.save,
            canMarkReady: true,
            canSaveDraft: true,
            isSaving: false,
            remainingDraftCount: 0,
            showsNextDraftQueue: false,
            onSaveReady: {},
            onSaveDraft: {},
            onNextDraft: {}
        )
    }

    private func fit<V: View>(_ view: V, in size: CGSize) -> CGSize {
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.bounds = CGRect(origin: .zero, size: size)
        return host.sizeThatFits(in: size)
    }
}
