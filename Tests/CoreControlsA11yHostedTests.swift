import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// Hosted coverage for the board and wardrobe controls #88 changed.
/// Walks the real SwiftUI accessibility tree. This is not a VoiceOver cursor walk.
@MainActor
final class CoreControlsA11yHostedTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var window: UIWindow?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "CoreControlsA11yHostedTests.\(UUID().uuidString)"
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

    func testBoardTilesExposeSeparateNamedActions() async throws {
        let model = try await makeBoardModel()
        var swapped = false
        try render(
            OutfitBoardView(
                model: model,
                onSwap: { _ in swapped = true },
                onWear: {},
                onChangeAnchor: {}
            ),
            size: CGSize(width: 390, height: 844)
        )

        let change = try XCTUnwrap(button("Change starting item"), describedLabels())
        let swap = try XCTUnwrap(button("Swap"), describedLabels())
        let keep = try XCTUnwrap(button("Keep"), describedLabels())
        let find = try XCTUnwrap(button("Find footwear"), describedLabels())
        XCTAssertNotEqual(ObjectIdentifier(swap.object), ObjectIdentifier(keep.object))
        XCTAssertFalse(change.traits.contains(.notEnabled))
        XCTAssertFalse(swap.traits.contains(.notEnabled))
        XCTAssertFalse(keep.traits.contains(.notEnabled))
        XCTAssertFalse(find.traits.contains(.notEnabled))
        XCTAssertFalse(customActionNames().contains("Swap"))
        XCTAssertFalse(customActionNames().contains("Find footwear"))
        XCTAssertFalse(swapped)
    }

    func testRejectedDeviceAccessDisablesFindAndSwapButNotKeep() async throws {
        let model = try await makeBoardModel()
        model.markDeviceAccessRejected()
        var swapped = false
        try render(
            OutfitBoardView(
                model: model,
                onSwap: { _ in swapped = true },
                onWear: {},
                onChangeAnchor: {}
            ),
            size: CGSize(width: 390, height: 844)
        )

        let change = try XCTUnwrap(button("Change starting item"), describedLabels())
        let swap = try XCTUnwrap(button("Swap"), describedLabels())
        let keep = try XCTUnwrap(button("Keep"), describedLabels())
        let find = try XCTUnwrap(button("Find footwear"), describedLabels())
        XCTAssertTrue(change.traits.contains(.notEnabled))
        XCTAssertTrue(swap.traits.contains(.notEnabled))
        XCTAssertTrue(find.traits.contains(.notEnabled))
        XCTAssertFalse(keep.traits.contains(.notEnabled))
        XCTAssertFalse(customActionNames().contains("Swap"))
        XCTAssertFalse(customActionNames().contains("Find footwear"))
        _ = swap.object.accessibilityActivate()
        pump()
        XCTAssertFalse(swapped)
    }

    func testSelectedWardrobeChipUsesSelectedTrait() async throws {
        let model = try await makeEmptyWardrobe()
        try render(
            WardrobeGridView(model: model, onSelect: { _ in }, onBuild: { _ in }),
            size: CGSize(width: 390, height: 844)
        )

        let before = try XCTUnwrap(button("Available"), describedLabels())
        XCTAssertFalse(before.traits.contains(.selected))
        XCTAssertTrue(before.object.accessibilityActivate())
        pump()

        let after = try XCTUnwrap(button("Available"), describedLabels())
        XCTAssertTrue(after.traits.contains(.selected))
        XCTAssertFalse(nodes().contains { $0.label?.localizedCaseInsensitiveContains("checkmark") == true })
    }

    func testLargestTextKeepsActionLabelsAndMinimumHeight() async throws {
        let board = try await makeBoardModel()
        try render(
            OutfitBoardView(model: board, onSwap: { _ in }, onWear: {}),
            size: CGSize(width: 320, height: 700),
            category: .accessibilityExtraExtraExtraLarge
        )
        let change = try XCTUnwrap(button("Change starting item"), describedLabels())
        XCTAssertEqual(change.label, "Change starting item")
        XCTAssertFalse(change.label?.contains("…") == true)
        XCTAssertGreaterThanOrEqual(change.frame.height, 44)

        let wardrobe = try await makeEmptyWardrobe()
        try render(
            WardrobeGridView(model: wardrobe, onSelect: { _ in }, onBuild: { _ in }),
            size: CGSize(width: 320, height: 700),
            category: .accessibilityExtraExtraExtraLarge
        )
        let available = try XCTUnwrap(button("Available"), describedLabels())
        XCTAssertEqual(available.label, "Available")
        XCTAssertGreaterThan(available.frame.width, 80, "Filter label must have visible width inside its horizontal scroll row")
        XCTAssertGreaterThanOrEqual(available.frame.height, 44)
    }

    // MARK: - Host

    private func makeBoardModel() async throws -> LoopDemoModel {
        let shirt = garment(name: "Navy Oxford Shirt", slot: .top)
        let pants = garment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: shirt.id, gapReason: nil, isAnchor: true),
                StubOutfitAssignment(slot: .bottom, garmentId: pants.id, gapReason: nil, isAnchor: false),
                StubOutfitAssignment(slot: .footwear, garmentId: nil, gapReason: "No footwear ready", isAnchor: false),
            ],
            rationaleSummary: "synthetic board",
            offlineCached: false
        )
        model.outfitWearable = true
        return model
    }

    private func makeEmptyWardrobe() async throws -> LoopDemoModel {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        return model
    }

    private func garment(name: String, slot: StubSlot) -> StubGarment {
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

    private func render<V: View>(
        _ root: V,
        size: CGSize,
        category: UIContentSizeCategory = .large
    ) throws {
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = category
        let hosted = UIWindow(frame: CGRect(origin: .zero, size: size))
        hosted.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        hosted.rootViewController = host
        hosted.makeKeyAndVisible()
        host.view.frame = hosted.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        hosted.layoutIfNeeded()
        pump()
        window = hosted
    }

    private func pump() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    private struct AXNode {
        let object: NSObject
        let label: String?
        let traits: UIAccessibilityTraits
        let frame: CGRect
    }

    private func button(_ label: String) -> AXNode? {
        nodes().first { $0.label == label && $0.object is HostedDailyWearA11yButton }
    }

    private func describedLabels() -> String {
        let labels = nodes()
            .filter { $0.object is HostedDailyWearA11yButton }
            .compactMap(\.label)
        return labels.joined(separator: " | ")
    }

    private func nodes() -> [AXNode] {
        var result: [AXNode] = []
        var seen = Set<ObjectIdentifier>()
        walk(window, seen: &seen) { object in
            let label = visibleLabel(object)
            guard let label, !label.isEmpty else { return }
            let frame: CGRect
            if let view = object as? UIView, let window {
                frame = view.convert(view.bounds, to: window)
            } else {
                frame = object.accessibilityFrame
            }
            result.append(AXNode(object: object, label: label, traits: object.accessibilityTraits, frame: frame))
        }
        return result
    }

    private func visibleLabel(_ object: NSObject) -> String? {
        if let label = object.accessibilityLabel, !label.isEmpty { return label }
        if let button = object as? UIButton {
            if let title = button.currentTitle, !title.isEmpty { return title }
            if let title = button.configuration?.title, !title.isEmpty { return title }
        }
        if let label = object as? UILabel, let text = label.text, !text.isEmpty { return text }
        return nil
    }

    private func customActionNames() -> [String] {
        var names: [String] = []
        var seen = Set<ObjectIdentifier>()
        walk(window, seen: &seen) { object in
            names.append(contentsOf: object.accessibilityCustomActions?.map(\.name) ?? [])
        }
        return names
    }

    private func walk(_ root: Any?, seen: inout Set<ObjectIdentifier>, visit: (NSObject) -> Void) {
        guard let object = root as? NSObject else { return }
        let identity = ObjectIdentifier(object)
        guard seen.insert(identity).inserted else { return }
        visit(object)
        if let view = object as? UIView {
            for sub in view.subviews { walk(sub, seen: &seen, visit: visit) }
            if let elements = view.accessibilityElements {
                for child in elements { walk(child, seen: &seen, visit: visit) }
            }
            let count = view.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let child = view.accessibilityElement(at: index) {
                        walk(child, seen: &seen, visit: visit)
                    }
                }
            }
        } else {
            if let elements = object.accessibilityElements {
                for child in elements { walk(child, seen: &seen, visit: visit) }
            }
            let count = object.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) {
                        walk(child, seen: &seen, visit: visit)
                    }
                }
            }
        }
    }
}
