import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// #280 hosted wear chrome. Walks UIKit views **and** `accessibilityElements`
/// (same pattern as PhotoReplaceHostedTests) so Log/Update, picker rows, board
/// wear, Logged today, and success actions can be discovered, measured, and
/// activated. Physical VoiceOver rotor / TestFlight remain UNVERIFIED_PHONE.
@MainActor
final class DailyWearA11yHostedTests: XCTestCase {
    private let seSize = CGSize(width: 375, height: 667)
    private let keyboardHeight: CGFloat = 260

    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var window: UIWindow?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "DailyWearA11yHostedTests.\(UUID().uuidString)"
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

    func testWearPickerDiscoversRowsAndActivatesSubmitOnSEAX5() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        var laundry = disposableGarment(name: "Ink Trousers", slot: .bottom)
        laundry.availability = "LAUNDRY"
        let model = await loadedModel(garments: [shirt, laundry])
        model.outfit = outfit(anchor: shirt, extra: laundry)

        let finished = expectation(description: "picker submit finished")
        try render(
            NavigationStack {
                WearConfirmView(model: model, onFinished: { finished.fulfill() })
            }
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            size: seSize
        )

        XCTAssertTrue(navTitles().contains(DailyWearCopy.pickerTitle))

        let rowId = "dailyWear.picker.row.\(shirt.id.uuidString)"
        let row = try XCTUnwrap(findNode(identifier: rowId), "picker row must be an accessibility element")
        XCTAssertEqual(row.label, DailyWearCopy.pickerRowLabel(shirt))
        XCTAssertEqual(row.value, DailyWearCopy.selectedValue)
        XCTAssertFalse((row.label ?? "").isEmpty)
        assertVisibleTarget(row, in: seSize)

        let laundryRow = try XCTUnwrap(
            findNode(identifier: "dailyWear.picker.row.\(laundry.id.uuidString)"),
            "unavailable row must stay its own control"
        )
        XCTAssertEqual(laundryRow.label, DailyWearCopy.pickerRowLabel(laundry))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(laundryRow.label ?? ""))

        let submit = try XCTUnwrap(
            findNode(identifier: "dailyWear.picker.submit"),
            "Log/Update must be discoverable"
        )
        XCTAssertEqual(
            submit.label,
            DailyWearCopy.submitAccessibilityLabel(isCorrection: false, selectionEmpty: false)
        )
        XCTAssertEqual(submit.hint, DailyWearCopy.submitHintNew)
        assertVisibleTarget(submit, in: seSize)

        let hostedSubmit = try XCTUnwrap(submit.object as? HostedDailyWearA11yButton)
        XCTAssertNotNil(hostedSubmit.onTap, "submit must keep a tap handler")
        XCTAssertTrue(hostedSubmit.accessibilityActivate(), "VoiceOver activate must fire Log selected")
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertTrue(model.hasLoggedToday, model.wearConfirmedMessage ?? "logged today after activate")
    }

    func testHostedButtonStoredFlagBlocksActivateWhenControlIsEnabled() {
        let button = HostedDailyWearA11yButton()
        var fired = 0
        button.onTap = { fired += 1 }
        button.allowsActivation = false
        button.isEnabled = true
        XCTAssertFalse(button.accessibilityActivate())
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(fired, 0)
        button.allowsActivation = true
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(fired, 1)
    }

    func testDisabledPickerSubmitDoesNotActivateOrPersist() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let model = await loadedModel(garments: [shirt])

        var finished = false
        try render(
            NavigationStack {
                WearConfirmView(model: model, onFinished: { finished = true })
            },
            size: seSize
        )

        let submit = try XCTUnwrap(findNode(identifier: "dailyWear.picker.submit"))
        let hosted = try XCTUnwrap(submit.object as? HostedDailyWearA11yButton)
        XCTAssertFalse(hosted.allowsActivation)
        XCTAssertTrue(submit.traits.contains(.notEnabled))
        XCTAssertFalse(hosted.accessibilityActivate())
        hosted.sendActions(for: .touchUpInside)
        pump()
        XCTAssertFalse(finished)
        XCTAssertFalse(model.hasLoggedToday)
        XCTAssertNil(model.wearConfirmedMessage)
    }

    func testWearPickerSubmitStaysVisibleAboveSearchKeyboardOnSEAX5() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let model = await loadedModel(garments: [shirt])
        model.outfit = outfit(anchor: shirt)

        try render(
            NavigationStack { WearConfirmView(model: model) }
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            size: seSize,
            keyboardInset: keyboardHeight
        )

        focusSearchField()
        pump()

        let submit = try XCTUnwrap(
            findNode(identifier: "dailyWear.picker.submit"),
            "submit must remain in the tree with search + keyboard"
        )
        let remainingHeight = seSize.height - keyboardHeight
        assertVisibleTarget(submit, in: CGSize(width: seSize.width, height: remainingHeight))
        XCTAssertLessThanOrEqual(
            submit.frame.maxY,
            remainingHeight + 1,
            "Log/Update (\(submit.frame)) must sit above a \(keyboardHeight) pt keyboard on SE"
        )
    }

    func testWearSuccessActionsAreVisibleAndActivatableOnSEAX5() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let model = await loadedModel(garments: [shirt])
        let completion = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(completion, .popToWardrobe)

        var done = false
        var change = false
        try render(
            NavigationStack {
                WearSuccessView(
                    model: model,
                    onDone: { done = true },
                    onChangeWhatIWore: { change = true }
                )
            }
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            size: seSize
        )

        let titleNode = try XCTUnwrap(
            findNode(identifier: "dailyWear.success.title"),
            "success title must be a spoken heading"
        )
        XCTAssertEqual(titleNode.label, DailyWearCopy.successTitle)

        let doneNode = try XCTUnwrap(findNode(identifier: "dailyWear.success.done"))
        let changeNode = try XCTUnwrap(findNode(identifier: "dailyWear.success.change"))
        let undoNode = try XCTUnwrap(findNode(identifier: "dailyWear.success.undo"))
        assertVisibleTarget(doneNode, in: seSize)
        assertVisibleTarget(changeNode, in: seSize)
        assertVisibleTarget(undoNode, in: seSize)
        XCTAssertEqual(changeNode.hint, DailyWearCopy.submitHintCorrection)
        XCTAssertEqual(undoNode.label, "Undo today’s wear")

        XCTAssertTrue(changeNode.object.accessibilityActivate())
        pump()
        XCTAssertTrue(change)

        XCTAssertTrue(doneNode.object.accessibilityActivate())
        pump()
        XCTAssertTrue(done)
    }

    func testBoardWearPrimaryActivatesCorrection() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        var draft = disposableGarment(name: "Untitled Top", slot: .top)
        draft.readiness = .draft
        let model = await loadedModel(garments: [shirt, draft])
        model.outfit = outfit(anchor: draft)
        model.outfitWearable = false

        var wore = false
        try render(
            NavigationStack {
                OutfitBoardView(
                    model: model,
                    onSwap: { _ in },
                    onWear: { wore = true },
                    onChangeWhatIWore: {}
                )
            },
            size: CGSize(width: 390, height: 844)
        )
        let disabled = try XCTUnwrap(findNode(identifier: "dailyWear.boardPrimary"))
        let disabledHost = try XCTUnwrap(disabled.object as? HostedDailyWearA11yButton)
        XCTAssertTrue(disabled.label?.contains(DailyWearCopy.wearingThis) == true)
        XCTAssertFalse(disabledHost.allowsActivation)
        XCTAssertTrue(disabled.traits.contains(.notEnabled))
        XCTAssertFalse(disabledHost.accessibilityActivate())
        disabledHost.sendActions(for: .touchUpInside)
        pump()
        XCTAssertFalse(wore)
        XCTAssertFalse(model.hasLoggedToday)
        XCTAssertTrue(navTitles().contains("Outfit"))

        model.outfit = outfit(anchor: shirt)
        model.outfitWearable = true
        let logged = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(logged, .popToWardrobe)

        var changed = false
        try render(
            NavigationStack {
                OutfitBoardView(
                    model: model,
                    onSwap: { _ in },
                    onWear: {},
                    onChangeWhatIWore: { changed = true }
                )
            },
            size: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(model.boardWearPrimary, .changeWhatIWore)
        let correction = try XCTUnwrap(findNode(identifier: "dailyWear.boardPrimary"))
        XCTAssertEqual(correction.label, DailyWearCopy.changeWhatIWore)
        XCTAssertEqual(correction.hint, DailyWearCopy.submitHintCorrection)
        assertVisibleTarget(correction, in: CGSize(width: 390, height: 844))
        XCTAssertTrue(correction.object.accessibilityActivate())
        pump()
        XCTAssertTrue(changed)
    }

    func testLoggedTodayRowActivatesAfterPersist() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let model = await loadedModel(garments: [shirt, pants])
        model.confirmProfile()
        let logged = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(logged, .popToWardrobe)
        model.outfit = outfit(anchor: pants)
        XCTAssertTrue(model.showsLoggedTodayRow)

        var opened = false
        try render(
            NavigationStack {
                WardrobeGridView(
                    model: model,
                    onSelect: { _ in },
                    onBuild: { _ in },
                    onOpenLoggedToday: { opened = true }
                )
            },
            size: CGSize(width: 390, height: 844)
        )

        let row = try XCTUnwrap(findNode(identifier: "dailyWear.loggedToday"))
        let snapshot = try XCTUnwrap(model.loggedTodaySnapshot())
        let expected = DailyWearCopy.rowAccessibility(
            leadName: snapshot.leadName,
            extraCount: snapshot.extraCount,
            wornOn: snapshot.event.wornOn
        )
        XCTAssertEqual(row.label, expected)
        XCTAssertEqual(row.hint, DailyWearCopy.loggedTodayHint)
        XCTAssertFalse(DailyWearCopy.containsMachineToken(row.label ?? ""))
        assertVisibleTarget(row, in: CGSize(width: 390, height: 844))
        XCTAssertTrue(row.object.accessibilityActivate())
        pump()
        XCTAssertTrue(opened)
    }

    // MARK: - Host

    @discardableResult
    private func render<V: View>(_ root: V, size: CGSize, keyboardInset: CGFloat = 0) throws -> UIImage {
        let host = UIHostingController(rootView: root)
        let hosted = UIWindow(frame: CGRect(origin: .zero, size: size))
        hosted.rootViewController = host
        if keyboardInset > 0 {
            host.additionalSafeAreaInsets.bottom = keyboardInset
        }
        hosted.makeKeyAndVisible()
        host.view.frame = hosted.bounds
        host.view.layoutIfNeeded()
        hosted.layoutIfNeeded()
        pump()
        let image = UIGraphicsImageRenderer(size: hosted.bounds.size).image { _ in
            host.view.drawHierarchy(in: hosted.bounds, afterScreenUpdates: true)
        }
        window = hosted
        return image
    }

    private func applyKeyboardInset(_ height: CGFloat) {
        guard let host = window?.rootViewController else { return }
        host.additionalSafeAreaInsets.bottom = height
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        window?.layoutIfNeeded()
    }

    private func focusSearchField() {
        var focused = false
        walkAny(window) { object in
            if focused { return }
            if let bar = object as? UISearchBar {
                focused = bar.becomeFirstResponder()
            } else if let field = object as? UITextField, field != window?.rootViewController?.view {
                let placeholder = field.placeholder ?? ""
                if placeholder == DailyWearCopy.searchPrompt || field.accessibilityTraits.contains(.searchField) {
                    focused = field.becomeFirstResponder()
                }
            }
        }
        pump()
    }

    private func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private struct AXNode {
        let object: NSObject
        let identifier: String?
        let label: String?
        let value: String?
        let hint: String?
        let traits: UIAccessibilityTraits
        let frame: CGRect
    }

    private func findNode(identifier: String) -> AXNode? {
        let matches = nodes().filter { $0.identifier == identifier }
        let hosted = matches.filter { $0.object is HostedDailyWearA11yButton }
        let buttons = matches.filter { $0.object is UIButton }
        let pool = hosted.isEmpty ? (buttons.isEmpty ? matches : buttons) : hosted
        return pool.min { lhs, rhs in
            let lh = lhs.frame.height > 0 ? lhs.frame.height : .greatestFiniteMagnitude
            let rh = rhs.frame.height > 0 ? rhs.frame.height : .greatestFiniteMagnitude
            return lh < rh
        }
    }

    private func nodes() -> [AXNode] {
        var result: [AXNode] = []
        walkAny(window) { object in
            let identifier = axIdentifier(object)
            let label = object.accessibilityLabel
            let hint = object.accessibilityHint
            let value = object.accessibilityValue
            guard identifier != nil || label != nil else { return }
            let frame: CGRect
            if let view = object as? UIView, let window {
                frame = view.convert(view.bounds, to: window)
            } else {
                frame = object.accessibilityFrame
            }
            result.append(
                AXNode(
                    object: object,
                    identifier: identifier,
                    label: label,
                    value: value,
                    hint: hint,
                    traits: object.accessibilityTraits,
                    frame: frame
                )
            )
        }
        return result
    }

    private func axIdentifier(_ object: NSObject) -> String? {
        if let view = object as? UIView, let id = view.accessibilityIdentifier, !id.isEmpty {
            return id
        }
        if let identified = object as? UIAccessibilityIdentification,
           let id = identified.accessibilityIdentifier, !id.isEmpty {
            return id
        }
        return nil
    }

    private func walkAny(_ root: Any?, visit: (NSObject) -> Void) {
        guard let object = root as? NSObject else { return }
        visit(object)
        if let view = object as? UIView {
            for sub in view.subviews { walkAny(sub, visit: visit) }
            if let elements = view.accessibilityElements {
                for child in elements { walkAny(child, visit: visit) }
            }
        } else if let elements = object.accessibilityElements {
            for child in elements { walkAny(child, visit: visit) }
        }
    }

    private func assertVisibleTarget(_ node: AXNode, in canvas: CGSize) {
        let visible = CGRect(origin: .zero, size: canvas)
        XCTAssertFalse(
            node.frame.intersection(visible).isNull,
            "\(node.identifier ?? node.label ?? "?") frame \(node.frame) is outside \(canvas)"
        )
        XCTAssertGreaterThan(
            node.frame.intersection(visible).height,
            0,
            "\(node.identifier ?? "?") must intersect the canvas"
        )
        XCTAssertGreaterThanOrEqual(
            node.frame.height,
            44,
            "\(node.identifier ?? "?") measured height \(node.frame.height) must be at least 44"
        )
    }

    private func uiKitLabels() -> [String] {
        var labels: [String] = []
        walkAny(window) { object in
            if let label = object as? UILabel, let text = label.text { labels.append(text) }
        }
        return labels
    }

    private func navTitles() -> [String] {
        var titles: [String] = []
        walkAny(window) { object in
            guard let nav = object as? UINavigationBar else { return }
            for item in nav.items ?? [] {
                if let title = item.title { titles.append(title) }
            }
        }
        return titles
    }

    private func loadedModel(garments: [StubGarment]) async -> LoopDemoModel {
        let store = InMemoryPersistenceStore(garments: garments, sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        return model
    }

    private func disposableGarment(name: String, slot: StubSlot) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
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

    private func outfit(anchor: StubGarment, extra: StubGarment? = nil) -> StubOutfit {
        var assignments = [
            StubOutfitAssignment(slot: anchor.slot, garmentId: anchor.id, gapReason: nil, isAnchor: true),
        ]
        if let extra {
            assignments.append(
                StubOutfitAssignment(slot: extra.slot, garmentId: extra.id, gapReason: nil, isAnchor: false)
            )
        }
        return StubOutfit(
            id: UUID(),
            assignments: assignments,
            rationaleSummary: "a11y board",
            offlineCached: false
        )
    }
}
