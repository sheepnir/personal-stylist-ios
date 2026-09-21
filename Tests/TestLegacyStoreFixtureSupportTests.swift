import XCTest
import SwiftData
@testable import PersonalStylist

/// #220 Slice B — prove Support APIs reuse #215 fixtures (PendingCapture / V2 shells).
final class TestLegacyStoreFixtureSupportTests: XCTestCase {
    @MainActor
    func testV2VersionedSchemaIncludesOnboardingShells() {
        XCTAssertTrue(
            TestLegacyStoreFixtures.currentSchemaIncludesV2Shells(),
            "PersonalStylistSchemaV2 must list CaptureBatch/PendingCapture and related shells"
        )
        XCTAssertEqual(PersonalStylistSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        let v2Names = Set(PersonalStylistSchemaV2.models.map { String(describing: $0) })
        XCTAssertTrue(v2Names.contains(String(describing: PendingCaptureEntity.self)))
        XCTAssertTrue(v2Names.contains(String(describing: CaptureBatchEntity.self)))
        // V1 must not claim onboarding shells (inventory assertion helper surface).
        let v1Names = Set(PersonalStylistSchemaV1.models.map { String(describing: $0) })
        XCTAssertFalse(v1Names.contains(String(describing: PendingCaptureEntity.self)))
    }

    @MainActor
    func testOpenRow7PendingCaptureBatchViaSupportAPI() throws {
        let (cleanupRoot, _, container) = try TestModelContainers.makeFromLegacyFixture(
            .row7PendingCaptureBatch
        )
        defer {
            _ = container
            try? FileManager.default.removeItem(at: cleanupRoot)
        }

        let context = ModelContext(container)
        let shell = try TestLegacyStoreFixtures.fetchRow7PendingCaptureShell(in: context)
        XCTAssertEqual(shell.batch.id, LegacyStoreFixtures.FixedIDs.batch)
        XCTAssertEqual(shell.batch.captureIds, [LegacyStoreFixtures.FixedIDs.pendingCapture])
        XCTAssertEqual(shell.pending.id, LegacyStoreFixtures.FixedIDs.pendingCapture)
        XCTAssertEqual(shell.pending.batchId, LegacyStoreFixtures.FixedIDs.batch)
        XCTAssertEqual(shell.pending.reviewStateRaw, "PENDING")
        XCTAssertEqual(shell.pending.imageStateRaw, "SAVED")
        XCTAssertEqual(shell.pending.analysisStateRaw, "NOT_REQUESTED")

        let onboarding = try context.fetch(FetchDescriptor<OnboardingStateEntity>())
        XCTAssertEqual(onboarding.count, 0, "row-7 fixture is structure-only; no auto OnboardingState")
    }

    @MainActor
    func testRestartMigratedRow7PreservesPendingCapture() throws {
        let (cleanupRoot, storeURL, first) = try TestModelContainers.makeFromLegacyFixture(
            .row7PendingCaptureBatch
        )
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: cleanupRoot)
        }

        let firstShell = try TestLegacyStoreFixtures.fetchRow7PendingCaptureShell(
            in: ModelContext(first)
        )
        XCTAssertEqual(firstShell.pending.reviewStateRaw, "PENDING")

        alive = try TestModelContainers.restartMigrated(storeURL: storeURL, releasing: first)
        let second = try XCTUnwrap(alive)
        let secondShell = try TestLegacyStoreFixtures.fetchRow7PendingCaptureShell(
            in: ModelContext(second)
        )
        XCTAssertEqual(secondShell.batch.id, LegacyStoreFixtures.FixedIDs.batch)
        XCTAssertEqual(secondShell.pending.id, LegacyStoreFixtures.FixedIDs.pendingCapture)
        XCTAssertEqual(secondShell.pending.reviewStateRaw, "PENDING")
        alive = nil
    }

    @MainActor
    func testOpenRelatedLegacyFixturesViaSupportAPI() throws {
        // Draft + confirmed profile packages — same Support entry point #191 will use.
        for id in [LegacyStoreFixtureID.row3LegacyDraftProfile, .row4LegacyConfirmedProfile] {
            let (cleanupRoot, _, container) = try TestModelContainers.makeFromLegacyFixture(id)
            defer {
                _ = container
                try? FileManager.default.removeItem(at: cleanupRoot)
            }
            let context = ModelContext(container)
            let profiles = try context.fetch(FetchDescriptor<StyleProfileEntity>())
            XCTAssertEqual(profiles.count, 1, id.rawValue)
            let pending = try context.fetch(FetchDescriptor<PendingCaptureEntity>())
            XCTAssertEqual(pending.count, 0, "\(id.rawValue) has no PendingCapture rows")
        }
    }
}
