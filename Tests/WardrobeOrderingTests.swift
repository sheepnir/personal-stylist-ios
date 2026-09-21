import XCTest
import SwiftData
@testable import PersonalStylist

final class WardrobeOrderingTests: XCTestCase {
    private func garment(_ name: String, slot: StubSlot = .top, availability: String = "AVAILABLE", createdAt: Date? = nil) -> StubGarment {
        StubGarment(id: UUID(), displayName: name, slot: slot, readiness: .ready,
                    availability: availability, createdAt: createdAt)
    }

    func testWearingOrderIsIndependentOfResponseOrder() {
        let expected: [StubSlot] = [.outerwear, .jacket, .midLayer, .top, .bottom, .footwear, .accessory]
        for offset in expected.indices {
            let response = Array(expected[offset...]) + Array(expected[..<offset])
            XCTAssertEqual(response.sorted { $0.wearingOrderIndex < $1.wearingOrderIndex }, expected)
        }
    }

    @MainActor
    func testRetiredVisibilityDefaultsHiddenAndPersistsBothChoices() throws {
        let suite = "WardrobeOrderingTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let garments = [garment("Shirt"), garment("Retired", availability: "RETIRED")]
        let store = InMemoryPersistenceStore(garments: garments)
        let first = LoopDemoModel(store: store, preferences: preferences)
        first.garments = garments
        XCTAssertFalse(first.showRetired)
        XCTAssertEqual(first.visibleGarments.map(\.displayName), ["Shirt"])
        first.showRetired = true
        let second = LoopDemoModel(store: store, preferences: preferences)
        second.garments = garments
        XCTAssertTrue(second.showRetired)
        XCTAssertEqual(second.visibleGarments.count, 2)
        second.showRetired = false
        XCTAssertFalse(LoopDemoModel(store: store, preferences: preferences).showRetired)
    }

    @MainActor
    func testIntakeTimestampSurvivesPersistenceAndEditing() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = garment("A old", createdAt: now.addingTimeInterval(-100))
        let new = garment("Z new", createdAt: now)
        for item in [old, new] { context.insert(StubEntityMapper.makeEntity(from: item)) }
        try context.save()
        let reloaded = try ModelContext(container).fetch(FetchDescriptor<GarmentEntity>())
        let sorted = reloaded.map { StubEntityMapper.stub(from: $0) }
            .sorted { $0.intakeSortDate(referenceDate: now) > $1.intakeSortDate(referenceDate: now) }
        XCTAssertEqual(sorted.map(\.displayName), ["Z new", "A old"])
        let entity = try XCTUnwrap(reloaded.first { $0.id == old.id })
        var edited = StubEntityMapper.stub(from: entity)
        edited.displayName = "Edited"
        StubEntityMapper.apply(edited, to: entity)
        XCTAssertEqual(entity.createdAt, old.createdAt)
    }

    func testLegacyIntakeAgeAndMissingDateFallback() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var old = garment("Old fixture")
        old.daysSinceIntake = 30
        XCTAssertEqual(old.intakeSortDate(referenceDate: now), now.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(garment("Unknown").intakeSortDate(referenceDate: now), now)
    }
}
