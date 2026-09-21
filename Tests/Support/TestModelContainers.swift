import Foundation
import SwiftData
@testable import PersonalStylist

/// Per-test SwiftData helpers for #220 (slice A in-memory/restart; slice B legacy fixtures).
///
/// Lives entirely under `Tests/Support/` — does **not** extend `AppModelContainer`
/// (Persistence/SwiftData is owned by #215).
enum TestModelContainers {
    /// Fresh in-memory container — same path as production `AppModelContainer.make(inMemory: true)`.
    @MainActor
    static func makeInMemory() throws -> ModelContainer {
        try AppModelContainer.make(inMemory: true)
    }

    /// On-disk container at an explicit URL using the current app schema (relaunch simulation).
    @MainActor
    static func makeOnDisk(storeURL: URL) throws -> ModelContainer {
        let schema = AppModelContainer.schema
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Temporary on-disk store directory + open container. Caller must delete `directory` when done.
    @MainActor
    static func makeOnDiskTemp() throws -> (directory: URL, storeURL: URL, container: ModelContainer) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PSTestStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("PersonalStylistLocal.store")
        let container = try makeOnDisk(storeURL: storeURL)
        return (directory, storeURL, container)
    }

    /// Tear down `old` and reopen the model layer against the **same** on-disk URL (relaunch sim).
    @MainActor
    static func restart(storeURL: URL, releasing old: ModelContainer) throws -> ModelContainer {
        // Drop the only strong reference the test holds; SwiftData closes when last ref dies.
        _ = old
        return try makeOnDisk(storeURL: storeURL)
    }

    // MARK: - Slice B (#215 fixture reuse)

    /// Open a #215 legacy-store fixture through the migration plan.
    /// Delegates to `TestLegacyStoreFixtures` — does not fork generators.
    /// Caller must delete `cleanupRoot` after releasing `container`.
    @MainActor
    static func makeFromLegacyFixture(
        _ id: LegacyStoreFixtureID
    ) throws -> (cleanupRoot: URL, storeURL: URL, container: ModelContainer) {
        try TestLegacyStoreFixtures.openMigrated(id: id)
    }

    /// Relaunch simulation against a migrated #215 fixture store URL.
    @MainActor
    static func restartMigrated(
        storeURL: URL,
        releasing old: ModelContainer
    ) throws -> ModelContainer {
        _ = old
        return try LegacyStoreFixtures.openMigratedContainer(at: storeURL)
    }
}
