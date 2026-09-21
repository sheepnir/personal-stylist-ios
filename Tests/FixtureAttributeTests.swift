import XCTest
import SwiftData
@testable import PersonalStylist

final class FixtureAttributeTests: XCTestCase {
    func testFixtureGarmentsDecodePatternAndSurface() throws {
        let garments = FixtureWardrobeLoader.loadGarments()
        XCTAssertFalse(garments.isEmpty, "Bundled garments.json should load")
        let withPattern = garments.filter { $0.pattern != nil }
        let withSurface = garments.filter { $0.surface != nil }
        XCTAssertGreaterThanOrEqual(withPattern.count, 20)
        XCTAssertGreaterThanOrEqual(withSurface.count, 20)

        let navy = try XCTUnwrap(garments.first { $0.displayName == "Navy Oxford Shirt" })
        XCTAssertEqual(navy.pattern, "SOLID")
        XCTAssertEqual(navy.surface, "SMOOTH")
        XCTAssertNotNil(navy.colorPrimary)
        XCTAssertNotNil(navy.formality)
        XCTAssertNotNil(navy.warmth)
    }

    func testSampleCopyKeepsReadinessFieldsForSaveReadySheet() throws {
        let fixture = try XCTUnwrap(
            FixtureWardrobeLoader.loadGarments().first { $0.pattern != nil && $0.surface != nil }
        )
        let copy = StubGarment(
            id: UUID(),
            displayName: fixture.displayName,
            slot: fixture.slot,
            readiness: .draft,
            availability: "AVAILABLE",
            colorPrimary: fixture.colorPrimary,
            pattern: fixture.pattern,
            surface: fixture.surface,
            imagePath: fixture.imagePath,
            formality: fixture.formality,
            warmth: fixture.warmth,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(),
            displayNameSource: "DERIVED"
        )
        XCTAssertNotNil(copy.pattern)
        XCTAssertNotNil(copy.surface)
        XCTAssertNotNil(copy.formality)
        XCTAssertNotNil(copy.warmth)
        XCTAssertNotNil(copy.colorPrimary)
    }

    @MainActor
    func testPatternSurfaceBackfillRunsOnceAndPreservesClears() throws {
        let fixture = try XCTUnwrap(
            FixtureWardrobeLoader.loadGarments().first { $0.pattern != nil && $0.surface != nil }
        )
        let suite = "FixtureAttributeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let container = try AppModelContainer.make(inMemory: true)
        let store = SwiftDataPersistenceStore(container: container)

        // Simulate pre-#121 seed: READY fixture id with nil pattern/surface.
        var sparse = fixture
        sparse.pattern = nil
        sparse.surface = nil
        let context = container.mainContext
        context.insert(StubEntityMapper.makeEntity(from: sparse))
        try context.save()

        store.backfillFixturePatternSurfaceOnce(defaults: defaults)
        let afterFill = try XCTUnwrap(
            try context.fetch(FetchDescriptor<GarmentEntity>()).first { $0.id == fixture.id }
        )
        XCTAssertEqual(afterFill.pattern, fixture.pattern)
        XCTAssertEqual(afterFill.surface, fixture.surface)
        XCTAssertTrue(defaults.bool(forKey: SwiftDataPersistenceStore.fixturePatternSurfaceBackfillKey))

        // User clears pattern after migration — relaunch must not restore it.
        afterFill.pattern = nil
        afterFill.readinessRaw = StubReadiness.draft.rawValue
        try context.save()

        store.backfillFixturePatternSurfaceOnce(defaults: defaults)
        let afterRelaunch = try XCTUnwrap(
            try context.fetch(FetchDescriptor<GarmentEntity>()).first { $0.id == fixture.id }
        )
        XCTAssertNil(afterRelaunch.pattern)
        XCTAssertEqual(afterRelaunch.surface, fixture.surface)
    }

    @MainActor
    func testBackfillSkipsDraftRowsEvenBeforeFlag() throws {
        let fixture = try XCTUnwrap(
            FixtureWardrobeLoader.loadGarments().first { $0.pattern != nil && $0.surface != nil }
        )
        let suite = "FixtureAttributeTests.draft.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let container = try AppModelContainer.make(inMemory: true)
        let store = SwiftDataPersistenceStore(container: container)
        var draft = fixture
        draft.pattern = nil
        draft.surface = nil
        draft.readiness = .draft
        let context = container.mainContext
        context.insert(StubEntityMapper.makeEntity(from: draft))
        try context.save()

        store.backfillFixturePatternSurfaceOnce(defaults: defaults)
        let row = try XCTUnwrap(
            try context.fetch(FetchDescriptor<GarmentEntity>()).first { $0.id == fixture.id }
        )
        XCTAssertNil(row.pattern)
        XCTAssertNil(row.surface)
        XCTAssertTrue(defaults.bool(forKey: SwiftDataPersistenceStore.fixturePatternSurfaceBackfillKey))
    }
}
