import XCTest
import UIKit
import SwiftData
@testable import PersonalStylist

final class PerformanceFixesTests: XCTestCase {
    func testFixtureJSONObjectsAreCachedAcrossCalls() {
        let before = FixtureWardrobeLoader.garmentJSONDiskReads
        _ = FixtureWardrobeLoader.loadGarmentJSONObjects()
        let afterFirst = FixtureWardrobeLoader.garmentJSONDiskReads
        XCTAssertLessThanOrEqual(afterFirst - before, 1)
        _ = FixtureWardrobeLoader.loadGarmentJSONObjects()
        _ = FixtureWardrobeLoader.loadGarmentJSONObjects()
        XCTAssertEqual(FixtureWardrobeLoader.garmentJSONDiskReads, afterFirst)
    }

    func testPhotoDownscaleProducesSmallerJPEGThanFullDecodeWould() throws {
        // 2400×1600 solid JPEG — full decode is costly; ImageIO thumbnail should shrink.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1600))
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2400, height: 1600))
        }
        let full = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let down = try XCTUnwrap(UserGarmentPhotoStore.downscaledJPEGData(full, maxPixel: 400))
        XCTAssertLessThan(down.count, full.count)
        let thumb = try XCTUnwrap(UserGarmentPhotoStore.downscaledJPEGData(full, maxPixel: 200))
        XCTAssertLessThanOrEqual(thumb.count, down.count)
    }


    func testWearDayFetchDoesNotRequireFullTableForConfirm() async {
        let store = InMemoryPersistenceStore(garments: [])
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        try? await store.saveWearEvent(
            StubWearEvent(id: UUID(), garmentIds: [UUID()], wornOn: yesterday, voidedAt: nil, sourceOutfitId: nil)
        )
        try? await store.saveWearEvent(
            StubWearEvent(id: UUID(), garmentIds: [UUID()], wornOn: today, voidedAt: nil, sourceOutfitId: nil)
        )
        let dayRows = await store.fetchWearEvents(on: today)
        XCTAssertEqual(dayRows.count, 1)
        let all = await store.fetchWearEvents()
        XCTAssertEqual(all.count, 2)
        let aggregates = await store.fetchWearAggregates()
        XCTAssertEqual(aggregates.counts.values.reduce(0, +), 2)
    }

    func testLatencyBudgetCopy() {
        XCTAssertTrue(
            OutfitEngineClient.GenerationLatencyBudget.note(milliseconds: 3_000)
                .contains("4 s")
        )
        XCTAssertTrue(
            OutfitEngineClient.GenerationLatencyBudget.note(milliseconds: 9_000)
                .contains("over")
        )
    }

    @MainActor
    func testLegacyWearMigrationAfterNewWearAndVoid() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let store = SwiftDataPersistenceStore(container: container)
        let garmentId = UUID()
        let now = Date()
        let old = StubWearEvent(id: UUID(), garmentIds: [garmentId],
                               wornOn: now.addingTimeInterval(-86400))
        container.mainContext.insert(StubEntityMapper.makeEntity(from: old))
        try container.mainContext.save()
        var current = StubWearEvent(id: UUID(), garmentIds: [garmentId], wornOn: now)
        try await store.saveWearEvent(current)
        let totals = await store.fetchWearAggregates()
        XCTAssertEqual(totals.counts[garmentId], 2)
        XCTAssertEqual(totals.lastWorn[garmentId], now)
        current.voidedAt = now
        try await store.saveWearEvent(current)
        let corrected = await store.fetchWearAggregates()
        XCTAssertEqual(corrected.counts[garmentId], 1)
        XCTAssertEqual(corrected.lastWorn[garmentId], old.wornOn)
    }

    @MainActor
    func testConcurrentLegacyBackfillDoesNotDuplicateCounts() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let store = SwiftDataPersistenceStore(container: container)
        let garmentId = UUID()
        let event = StubWearEvent(id: UUID(), garmentIds: [garmentId], wornOn: Date(), voidedAt: nil, sourceOutfitId: nil)
        container.mainContext.insert(StubEntityMapper.makeEntity(from: event, userId: AppIdentity.defaultUserId))
        try container.mainContext.save()
        await withTaskGroup(of: WearAggregates.self) { group in
            for _ in 0..<12 { group.addTask { await store.fetchWearAggregates() } }
            for await result in group { XCTAssertEqual(result.counts[garmentId], 1) }
        }
        let final = await store.fetchWearAggregates()
        XCTAssertEqual(final.counts[garmentId], 1)
    }

    func testCreatedIndexKeepsFullMillisecondTimestamp() {
        let user = UUID(), garment = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(GarmentIndexKey.userCreated(user, createdAt: date, id: garment)
            .contains("|1800000000000|"))
    }
}
