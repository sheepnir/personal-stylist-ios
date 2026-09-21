import XCTest
@testable import PersonalStylist

/// D-72 / #120 wear-history copy and model-driven refresh after void.
/// Disposable in-memory fixtures only. Cancel is UI-only (no store write).
final class WearHistoryCopyTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "WearHistoryCopyTests.\(UUID().uuidString)"
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

    // MARK: - Copy

    func testVoidConfirmCopyNamesScopeAndOmitsMachineTokens() {
        let joined = [
            WearHistoryCopy.voidTitle,
            WearHistoryCopy.voidMessage,
            WearHistoryCopy.voidAction,
            WearHistoryCopy.voidConfirm,
            WearHistoryCopy.voidedLabel,
            WearHistoryCopy.empty,
            WearHistoryCopy.seeAll,
        ].joined(separator: "\n")

        XCTAssertEqual(WearHistoryCopy.voidTitle, "Void this wear?")
        XCTAssertEqual(WearHistoryCopy.voidConfirm, "Void wear")
        XCTAssertEqual(WearHistoryCopy.cancel, "Cancel")
        XCTAssertTrue(WearHistoryCopy.voidMessage.contains("cost per wear"))
        XCTAssertTrue(WearHistoryCopy.voidMessage.contains("voided"))
        XCTAssertFalse(WearHistoryCopy.voidMessage.contains("voidedAt"))
        XCTAssertFalse(WearHistoryCopy.voidMessage.contains("WearEvent"))

        for forbidden in ["HTTP", "http://", "https://", "NSURL", "token", "VOIDED", "sourceOutfitId"] {
            XCTAssertFalse(joined.contains(forbidden), "copy must not contain \(forbidden)")
        }
    }

    func testEmptyHistoryCopy() {
        XCTAssertEqual(WearHistoryCopy.empty, "No wears logged yet")
        XCTAssertFalse(WearHistoryCopy.empty.contains("[]"))
        XCTAssertFalse(WearHistoryCopy.empty.contains("nil"))
    }

    func testVoidedRowLabel() {
        XCTAssertEqual(WearHistoryCopy.voidedLabel, "Voided")
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let ax = WearHistoryCopy.rowAccessibility(wornOn: date, outfitName: "Canvas look", isVoided: true)
        XCTAssertTrue(ax.contains(WearHistoryCopy.voidedLabel))
        XCTAssertTrue(ax.contains("Canvas look"))
        XCTAssertFalse(ax.contains("voidedAt"))
        let live = WearHistoryCopy.rowAccessibility(wornOn: date, outfitName: "Canvas look", isVoided: false)
        XCTAssertFalse(live.contains(WearHistoryCopy.voidedLabel))
    }

    func testRowUsesOutfitNameWhenKnownAndFallsBackToDatedLine() {
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let named = WearHistoryCopy.rowLine(wornOn: date, outfitName: "Canvas look")
        XCTAssertTrue(named.contains("Canvas look"))
        XCTAssertTrue(named.contains("·"))

        let dated = WearHistoryCopy.rowLine(wornOn: date, outfitName: nil)
        XCTAssertTrue(dated.hasPrefix("Worn "))
        XCTAssertFalse(dated.contains("·"))

        let blank = WearHistoryCopy.rowLine(wornOn: date, outfitName: "   ")
        XCTAssertEqual(blank, dated)
    }

    func testResolvedOutfitNameUsesBoardLookOrWornPieces() {
        let top = disposableGarment(name: "Canvas Tee", slot: .top)
        let bottom = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let lookId = UUID()
        let look = StubOutfit(
            id: lookId,
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: top.id, gapReason: nil, isAnchor: true),
                StubOutfitAssignment(slot: .bottom, garmentId: bottom.id, gapReason: nil, isAnchor: false),
            ],
            rationaleSummary: "local",
            offlineCached: false
        )

        let fromBoard = WearHistoryCopy.resolvedOutfitName(
            sourceOutfitId: lookId,
            currentOutfit: look,
            wornGarmentIds: [top.id],
            garments: [top, bottom]
        )
        XCTAssertEqual(fromBoard, "Canvas Tee, Ink Trousers")

        let fromEvent = WearHistoryCopy.resolvedOutfitName(
            sourceOutfitId: UUID(),
            currentOutfit: look,
            wornGarmentIds: [top.id, bottom.id],
            garments: [top, bottom]
        )
        XCTAssertEqual(fromEvent, "Canvas Tee, Ink Trousers")

        XCTAssertNil(
            WearHistoryCopy.resolvedOutfitName(
                sourceOutfitId: nil,
                currentOutfit: look,
                wornGarmentIds: [top.id, bottom.id],
                garments: [top, bottom]
            )
        )
    }

    func testCancelLeavesStoreUnchanged() async throws {
        let coat = disposableGarment(name: "Canvas Coat", slot: .outerwear)
        let store = InMemoryPersistenceStore(garments: [coat], defaults: defaults)
        let event = StubWearEvent(id: UUID(), garmentIds: [coat.id], wornOn: Date())
        try await store.saveWearEvent(event)
        let before = await store.fetchWearEvents()
        XCTAssertEqual(WearHistoryCopy.cancel, "Cancel")
        XCTAssertEqual(before.map(\.id), [event.id])
        XCTAssertTrue(before.allSatisfy { $0.voidedAt == nil })
        let after = await store.fetchWearEvents()
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertTrue(after.allSatisfy { $0.voidedAt == nil })
    }

    // MARK: - Model-driven history + CPW refresh

    @MainActor
    func testVoidWearRefreshesCountsAndCostPerWearCopy() async throws {
        var coat = disposableGarment(name: "Canvas Coat", slot: .outerwear)
        coat.purchasePrice = Decimal(100)
        coat.purchaseCurrency = "USD"
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [coat, pants], sets: [], defaults: defaults)
        let older = Date(timeIntervalSince1970: 1_724_000_000)
        let newer = Date(timeIntervalSince1970: 1_726_000_000)
        let pair = StubWearEvent(
            id: UUID(),
            garmentIds: [coat.id, pants.id],
            wornOn: older,
            sourceOutfitId: UUID()
        )
        let solo = StubWearEvent(id: UUID(), garmentIds: [coat.id], wornOn: newer)
        try await store.saveWearEvent(pair)
        try await store.saveWearEvent(solo)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        XCTAssertEqual(model.wearCount(for: coat.id), 2)
        XCTAssertEqual(model.recentWearHistory(for: coat.id).map(\.id), [solo.id, pair.id])
        XCTAssertEqual(model.wearHistoryAll(for: coat.id).count, 2)
        let before = CostPerWearCopy.summary(for: coat, confirmedWears: model.wearCount(for: coat.id))
        XCTAssertTrue(before.wearLine.contains("2"))

        await model.voidWear(id: pair.id)

        XCTAssertEqual(model.wearCount(for: coat.id), 1)
        XCTAssertEqual(model.recentWearHistory(for: coat.id).map(\.id), [solo.id])
        let all = model.wearHistoryAll(for: coat.id)
        XCTAssertEqual(all.count, 2)
        let voided = try XCTUnwrap(all.first { $0.id == pair.id })
        XCTAssertTrue(voided.isVoided)
        XCTAssertEqual(
            WearHistoryCopy.rowAccessibility(wornOn: voided.wornOn, outfitName: nil, isVoided: true),
            WearHistoryCopy.rowLine(wornOn: voided.wornOn, outfitName: nil) + ". " + WearHistoryCopy.voidedLabel
        )
        let after = CostPerWearCopy.summary(
            for: try XCTUnwrap(model.garments.first { $0.id == coat.id }),
            confirmedWears: model.wearCount(for: coat.id)
        )
        XCTAssertTrue(after.wearLine.contains("1"))
        XCTAssertNotEqual(before.cpwLine, after.cpwLine)
        XCTAssertEqual(after.addPriceTitle, "Edit price")
    }

    // MARK: - Helpers

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
