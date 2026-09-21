import Foundation
import SwiftData

enum AppModelContainer {
    static let storeName = "PersonalStylistLocal"

    /// Current (V2) schema.
    static let schema = Schema(versionedSchema: PersonalStylistSchemaV2.self)

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try openCurrent(configurations: [config], runUnversionedPostOpen: !inMemory)
    }

    /// Open a disk store at `url` with the V2 schema + migration plan (#215 / #220 helper).
    static func make(at url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, url: url)
        return try openCurrent(configurations: [config], runUnversionedPostOpen: true)
    }

    /// Write-only container stamped as a legacy schema version (fixture generation).
    static func makeLegacyWriter(
        versionedSchema: any VersionedSchema.Type,
        at url: URL
    ) throws -> ModelContainer {
        let legacySchema = Schema(versionedSchema: versionedSchema)
        let config = ModelConfiguration(schema: legacySchema, url: url)
        return try ModelContainer(for: legacySchema, configurations: [config])
    }

    /// Prefer staged `PersonalStylistMigrationPlan`. Unversioned pre-#215 stores have no
    /// model version metadata — staged migration throws `unknownDataStoreSchema` /
    /// NSCocoaError 134504. Open those with automatic lightweight migration **without
    /// deleting the store**, then run the same post-open reconcile/backfill hooks.
    private static func openCurrent(
        configurations: [ModelConfiguration],
        runUnversionedPostOpen: Bool
    ) throws -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: PersonalStylistMigrationPlan.self,
                configurations: configurations
            )
        } catch {
            guard isUnknownModelVersionError(error) else { throw error }
            let container = try ModelContainer(for: schema, configurations: configurations)
            if runUnversionedPostOpen {
                finishUnversionedUpgrade(container: container)
            }
            return container
        }
    }

    /// Pre-#215 stores were created with a plain `Schema([...])` and have no version stamp.
    private static func isUnknownModelVersionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == 134504 { return true }
        let text = String(describing: error).lowercased()
        return text.contains("unknowndatastoreschema")
            || text.contains("unknown model version")
            || text.contains("unknown data store schema")
    }

    /// Mirrors →V2 didMigrate side effects for stores that never had a VersionedSchema stamp.
    private static func finishUnversionedUpgrade(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        FixturePatternSurfaceBackfill.runIfNeeded(in: context, defaults: .standard)
        GarmentPhotoReferenceReconciliation.reconcile(in: context)
        try? context.save()
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey)
        defaults.set(true, forKey: PersonalStylistMigrationPlan.schemaV2MigrationCompletedKey)
    }
}
