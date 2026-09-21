import XCTest
import SwiftData
@testable import PersonalStylist

/// In-memory + on-disk restart helpers (#220 slice A — no #215 migration fixtures).
final class TestModelContainerTests: XCTestCase {
    @MainActor
    func testInMemoryContainerRoundTripsGarment() throws {
        let container = try TestModelContainers.makeInMemory()
        let context = container.mainContext
        let id = UUID()
        context.insert(
            GarmentEntity(
                id: id,
                userId: AppIdentity.defaultUserId,
                displayName: "Test Tee",
                slotRaw: StubSlot.top.rawValue,
                readinessRaw: StubReadiness.draft.rawValue,
                availability: "AVAILABLE",
                createdAt: Date()
            )
        )
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GarmentEntity>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, id)
    }

    @MainActor
    func testRestartReopensSameOnDiskStore() throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let id = UUID()
        let firstContext = first.mainContext
        firstContext.insert(
            GarmentEntity(
                id: id,
                userId: AppIdentity.defaultUserId,
                displayName: "Persisted Coat",
                slotRaw: StubSlot.outerwear.rawValue,
                readinessRaw: StubReadiness.ready.rawValue,
                availability: "AVAILABLE",
                createdAt: Date()
            )
        )
        try firstContext.save()

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let second = try XCTUnwrap(alive)
        let rows = try second.mainContext.fetch(FetchDescriptor<GarmentEntity>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].displayName, "Persisted Coat")
        XCTAssertEqual(rows[0].id, id)
        alive = nil
    }
}
