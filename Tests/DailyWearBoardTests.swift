import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// D-75 presentation: same-day board primary is explicit correction and does not persist.
final class DailyWearBoardTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "DailyWearBoardTests.\(UUID().uuidString)"
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

    func testBoardPrimaryResolverSwitchesLabelAndPersistFlag() {
        let logged = DailyWearBoardPrimary.resolve(hasLoggedToday: true)
        XCTAssertEqual(logged, .changeWhatIWore)
        XCTAssertEqual(logged.title, DailyWearCopy.changeWhatIWore)
        XCTAssertFalse(logged.persistsFromBoard)
        XCTAssertEqual(logged.accessibilityHint, DailyWearCopy.submitHintCorrection)

        let fresh = DailyWearBoardPrimary.resolve(hasLoggedToday: false)
        XCTAssertEqual(fresh, .wearingThis)
        XCTAssertEqual(fresh.title, DailyWearCopy.wearingThis)
        XCTAssertTrue(fresh.persistsFromBoard)
    }

    @MainActor
    func testSameDayBoardPrimaryCallbackDoesNotPersist() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let logged = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(logged, .popToWardrobe)
        let priorId = try XCTUnwrap(model.loggedTodayEvent()?.id)

        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .bottom, garmentId: pants.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "same-day new board",
            offlineCached: false
        )
        model.outfitWearable = true
        XCTAssertEqual(model.boardWearPrimary, .changeWhatIWore)

        var wearCalled = false
        var changeCalled = false
        let board = OutfitBoardView(
            model: model,
            onSwap: { _ in },
            onWear: { wearCalled = true },
            onChangeWhatIWore: { changeCalled = true }
        )
        // Presentation smoke: the hosted type accepts the correction callback.
        _ = UIHostingController(rootView: board)
        // Same path ContentView wires: correction opens the picker and writes nothing.
        board.onChangeWhatIWore()
        XCTAssertTrue(changeCalled)
        XCTAssertFalse(wearCalled)
        XCTAssertFalse(model.boardWearPrimary.persistsFromBoard)

        XCTAssertEqual(model.loggedTodayEvent()?.id, priorId)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertEqual(model.wearCount(for: pants.id), 0)
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
}
