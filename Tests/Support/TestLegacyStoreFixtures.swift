import Foundation
import SwiftData
@testable import PersonalStylist

/// #220 Slice B — thin wrappers over #215 `LegacyStoreFixtures` for #220 / later #191.
///
/// Reuses versioned-schema disk packages and `openMigratedContainer` — does **not**
/// fork schema, edit `Persistence/SwiftData/**`, or duplicate fixture generators.
enum TestLegacyStoreFixtures {
    /// V2 onboarding shell types from `PersonalStylistSchemaV2` (structure only).
    static let v2OnboardingShellTypes: [any PersistentModel.Type] = [
        OnboardingStateEntity.self,
        StyleProfileDraftEntity.self,
        PrivacyConsentEntity.self,
        CaptureBatchEntity.self,
        PendingCaptureEntity.self,
    ]

    /// Resource URL for a checked-in package under `Fixtures/LegacyStores/<id>/`, if present.
    static func bundledPackageURL(
        id: LegacyStoreFixtureID,
        in bundle: Bundle = Bundle(for: TestLegacyStoreFixturesBundleAnchor.self)
    ) -> URL? {
        bundle.resourceURL?
            .appendingPathComponent("Fixtures/LegacyStores/\(id.rawValue)", isDirectory: true)
    }

    /// Working package: prefer bundled copy, else generate via `LegacyStoreFixtures`.
    /// Caller must delete `cleanupRoot` when finished.
    @MainActor
    static func makeWorkingPackage(id: LegacyStoreFixtureID) throws -> (
        cleanupRoot: URL,
        packageDirectory: URL,
        storeURL: URL
    ) {
        let fm = FileManager.default
        if let bundled = bundledPackageURL(id: id), fm.fileExists(atPath: bundled.path) {
            let cleanupRoot = fm.temporaryDirectory
                .appendingPathComponent("PS220Legacy-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: cleanupRoot, withIntermediateDirectories: true)
            let packageDirectory = cleanupRoot.appendingPathComponent(id.rawValue, isDirectory: true)
            try fm.copyItem(at: bundled, to: packageDirectory)
            return (cleanupRoot, packageDirectory, LegacyStoreFixtures.storeURL(inPackage: packageDirectory))
        }

        let cleanupRoot = fm.temporaryDirectory
            .appendingPathComponent("PS220LegacyGen-\(UUID().uuidString)", isDirectory: true)
        let packageDirectory = cleanupRoot.appendingPathComponent(id.rawValue, isDirectory: true)
        try LegacyStoreFixtures.generate(id: id, at: packageDirectory)
        return (cleanupRoot, packageDirectory, LegacyStoreFixtures.storeURL(inPackage: packageDirectory))
    }

    /// Copy/generate a fixture package and open it with the #215 migration plan (V2).
    /// Caller must delete `cleanupRoot` when finished (after releasing `container`).
    @MainActor
    static func openMigrated(id: LegacyStoreFixtureID) throws -> (
        cleanupRoot: URL,
        storeURL: URL,
        container: ModelContainer
    ) {
        let working = try makeWorkingPackage(id: id)
        let container = try LegacyStoreFixtures.openMigratedContainer(at: working.storeURL)
        return (working.cleanupRoot, working.storeURL, container)
    }

    /// Whether `PersonalStylistSchemaV2.models` lists every onboarding shell type.
    static func currentSchemaIncludesV2Shells() -> Bool {
        let names = Set(PersonalStylistSchemaV2.models.map { String(describing: $0) })
        return v2OnboardingShellTypes.allSatisfy { names.contains(String(describing: $0)) }
    }

    /// Fetch the row-7 PendingCapture + CaptureBatch shells (stable FixedIDs from #215).
    static func fetchRow7PendingCaptureShell(
        in context: ModelContext
    ) throws -> (batch: CaptureBatchEntity, pending: PendingCaptureEntity) {
        let batches = try context.fetch(FetchDescriptor<CaptureBatchEntity>())
        guard let batch = batches.first else {
            throw TestLegacyStoreFixtureError.missingEntity("CaptureBatchEntity")
        }
        let pendingRows = try context.fetch(FetchDescriptor<PendingCaptureEntity>())
        guard let pending = pendingRows.first else {
            throw TestLegacyStoreFixtureError.missingEntity("PendingCaptureEntity")
        }
        return (batch, pending)
    }
}

enum TestLegacyStoreFixtureError: Error, CustomStringConvertible {
    case missingEntity(String)

    var description: String {
        switch self {
        case .missingEntity(let name):
            return "Expected \(name) in fixture store"
        }
    }
}

/// Bundle anchor so Support can resolve `Fixtures/LegacyStores` without depending on a test class.
private final class TestLegacyStoreFixturesBundleAnchor: NSObject {}
