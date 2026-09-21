import XCTest
import SwiftData
@testable import PersonalStylist

/// #215 — open/migrate/reopen real disk stores three times; no reseed, no loss, no loop.
final class SchemaMigrationTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "SchemaMigrationTests.\(UUID().uuidString)"
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

    func testV1DraftProfileMigratesWithoutLossOrReseed() async throws {
        try await assertMigrateReopenThreeTimes(id: .row3LegacyDraftProfile) { context, pass in
            let profiles = try context.fetch(FetchDescriptor<StyleProfileEntity>())
            XCTAssertEqual(profiles.count, 1, "pass \(pass)")
            let profile = try XCTUnwrap(profiles.first)
            XCTAssertEqual(profile.id, LegacyStoreFixtures.FixedIDs.draftProfile)
            XCTAssertNil(profile.confirmedAt)
            XCTAssertEqual(profile.version, 1)
            XCTAssertEqual(profile.profession, "Engineer")
            let garments = try context.fetch(FetchDescriptor<GarmentEntity>())
            XCTAssertEqual(garments.count, 0, "must not reseed wardrobe — pass \(pass)")
            let onboarding = try context.fetch(FetchDescriptor<OnboardingStateEntity>())
            XCTAssertEqual(onboarding.count, 0, "structure only; no auto OnboardingState — pass \(pass)")
        }
    }

    func testV1ConfirmedProfileMigratesWithoutLossOrReseed() async throws {
        try await assertMigrateReopenThreeTimes(id: .row4LegacyConfirmedProfile) { context, pass in
            let profiles = try context.fetch(FetchDescriptor<StyleProfileEntity>())
            XCTAssertEqual(profiles.count, 1, "pass \(pass)")
            let profile = try XCTUnwrap(profiles.first)
            XCTAssertEqual(profile.id, LegacyStoreFixtures.FixedIDs.confirmedProfile)
            XCTAssertNotNil(profile.confirmedAt)
            XCTAssertEqual(profile.version, 2)
            XCTAssertEqual(profile.seedSource, "founder-seed")
            let garments = try context.fetch(FetchDescriptor<GarmentEntity>())
            XCTAssertEqual(garments.count, 0, "must not reseed — pass \(pass)")
        }
    }

    func testSeededWardrobePreservesIDsWearAndPhotoRefs() async throws {
        try await assertMigrateReopenThreeTimes(id: .seededWardrobe) { context, pass in
            let garments = try context.fetch(FetchDescriptor<GarmentEntity>())
            let expectedCount = FixtureWardrobeLoader.loadGarments().count
            XCTAssertEqual(garments.count, expectedCount, "pass \(pass)")
            let photo = try XCTUnwrap(garments.first { $0.id == LegacyStoreFixtures.FixedIDs.photoGarment })
            XCTAssertEqual(photo.imagePath, LegacyStoreFixtures.FixedIDs.userPhotoPath)
            let primary = photo.images.first { $0.isPrimary }
            XCTAssertEqual(primary?.originalURI, LegacyStoreFixtures.FixedIDs.userPhotoPath,
                           "imagePath reconciled into GarmentImageEntity — pass \(pass)")
            let wears = try context.fetch(FetchDescriptor<WearEventEntity>())
            XCTAssertEqual(wears.count, 1, "pass \(pass)")
            XCTAssertEqual(wears.first?.id, LegacyStoreFixtures.FixedIDs.wearEvent)
            XCTAssertEqual(wears.first?.garmentIds, [LegacyStoreFixtures.FixedIDs.photoGarment])
            let sets = try context.fetch(FetchDescriptor<GarmentSetEntity>())
            XCTAssertEqual(sets.count, FixtureWardrobeLoader.loadSets().count, "pass \(pass)")
        }
    }

    func testMainShapedV1_1PreservesMembershipAndIndex() async throws {
        try await assertMigrateReopenThreeTimes(id: .mainShapedV1_1) { context, pass in
            let garments = try context.fetch(FetchDescriptor<GarmentEntity>())
            XCTAssertEqual(garments.count, 1, "pass \(pass)")
            let indexes = try context.fetch(FetchDescriptor<GarmentQueryIndex>())
            XCTAssertEqual(indexes.count, 1, "pass \(pass)")
            XCTAssertEqual(indexes.first?.garmentId, garments.first?.id)
            let memberships = try context.fetch(FetchDescriptor<WearMembershipEntity>())
            XCTAssertEqual(memberships.count, 1, "pass \(pass)")
            XCTAssertEqual(memberships.first?.eventId, LegacyStoreFixtures.FixedIDs.wearEvent)
        }
    }

    func testPendingCaptureBatchStableAcrossReopens() async throws {
        try await assertMigrateReopenThreeTimes(id: .row7PendingCaptureBatch) { context, pass in
            let batches = try context.fetch(FetchDescriptor<CaptureBatchEntity>())
            XCTAssertEqual(batches.count, 1, "pass \(pass)")
            XCTAssertEqual(batches.first?.id, LegacyStoreFixtures.FixedIDs.batch)
            XCTAssertEqual(batches.first?.captureIds, [LegacyStoreFixtures.FixedIDs.pendingCapture])
            let pending = try context.fetch(FetchDescriptor<PendingCaptureEntity>())
            XCTAssertEqual(pending.count, 1, "pass \(pass)")
            XCTAssertEqual(pending.first?.reviewStateRaw, "PENDING")
            XCTAssertEqual(pending.first?.batchId, LegacyStoreFixtures.FixedIDs.batch)
            let profiles = try context.fetch(FetchDescriptor<StyleProfileEntity>())
            XCTAssertEqual(profiles.count, 1, "pass \(pass)")
        }
    }

    func testPatternSurfaceBackfillSkippedAfterV2MigrationFlag() throws {
        defaults.set(true, forKey: PersonalStylistMigrationPlan.schemaV2MigrationCompletedKey)
        defaults.set(false, forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey)
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let fixture = try XCTUnwrap(FixtureWardrobeLoader.loadGarments().first)
        let entity = StubEntityMapper.makeEntity(from: fixture)
        entity.pattern = nil
        entity.surface = nil
        context.insert(entity)
        try context.save()
        FixturePatternSurfaceBackfill.runIfNeeded(in: context, defaults: defaults)
        let reloaded = try context.fetch(FetchDescriptor<GarmentEntity>()).first
        XCTAssertNil(reloaded?.pattern, "backfill must not run after V2 migration completed")
        XCTAssertTrue(defaults.bool(forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey))
    }

    // MARK: - Helpers

    @MainActor
    private func assertMigrateReopenThreeTimes(
        id: LegacyStoreFixtureID,
        assertPass: (ModelContext, Int) throws -> Void
    ) async throws {
        // #220 Support API — same working-package path later #191 will use.
        let working = try TestLegacyStoreFixtures.makeWorkingPackage(id: id)
        defer { try? FileManager.default.removeItem(at: working.cleanupRoot) }
        let storeURL = working.storeURL

        var previousGarmentCount: Int?
        for pass in 1...3 {
            // Fresh defaults each open except V2-complete may be set by migration didMigrate on suite defaults —
            // use isolated suite via injecting into migration is hard; clear V2 flags before first open only.
            if pass == 1 {
                defaults.removePersistentDomain(forName: defaultsSuiteName)
            }
            let container = try LegacyStoreFixtures.openMigratedContainer(at: storeURL)
            let context = ModelContext(container)
            try assertPass(context, pass)
            let garmentCount = try context.fetchCount(FetchDescriptor<GarmentEntity>())
            if let previousGarmentCount {
                XCTAssertEqual(garmentCount, previousGarmentCount, "garment count stable across reopen — pass \(pass)")
            }
            previousGarmentCount = garmentCount
            // Release container before reopen.
            _ = container
        }
    }
}
