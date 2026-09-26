import Foundation
import SwiftData

/// Disk-backed legacy SwiftData stores for migration tests (#215) and reuse by #220.
///
/// Stable API for #220:
/// - `LegacyStoreFixtureID` — fixture names aligned to PRD §3.1 rows
/// - `LegacyStoreFixtures.storeFileName` / `storeURL(inPackage:)`
/// - `LegacyStoreFixtures.openMigratedContainer(at:)` — V2 + `PersonalStylistMigrationPlan`
/// - `LegacyStoreFixtures.generate*(at:)` — write legacy packages (V1 / V1.1 / V2 row-7)
/// - `LegacyStoreFixtures.copyPackage(from:to:)` — clone a package before opening
///
/// Checked-in packages live under `Tests/Fixtures/LegacyStores/<id>/` (test bundle only).
/// Never delete a user store to “fix” migration failure.
enum LegacyStoreFixtureID: String, CaseIterable {
    /// PRD §3.1 row 3 — legacy draft StyleProfile (`confirmedAt == nil`), no OnboardingState.
    case row3LegacyDraftProfile = "row3-legacy-draft-profile"
    /// PRD §3.1 row 4 — legacy confirmed StyleProfile, no OnboardingState.
    case row4LegacyConfirmedProfile = "row4-legacy-confirmed-profile"
    /// PRD §3.1 row 7 — CaptureBatch with PendingCapture `reviewState == PENDING` (V2 structure).
    case row7PendingCaptureBatch = "row7-pending-capture-batch"
    /// Fixture-seeded wardrobe (09e292a-shaped V1 graph) with wear history + photo refs.
    case seededWardrobe = "seeded-wardrobe"
    /// Current-main-shaped V1.1 store (includes WearMembership + GarmentQueryIndex).
    case mainShapedV1_1 = "main-shaped-v1_1"
}

enum LegacyStoreFixtures {
    static let storeFileName = "PersonalStylistLocal.store"

    static func storeURL(inPackage packageURL: URL) -> URL {
        packageURL.appendingPathComponent(storeFileName)
    }

    /// Clone a package directory into a unique working folder (never mutate the source).
    static func copyPackage(from sourcePackage: URL, label: String) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePackage.path) else {
            throw LegacyStoreFixtureError.missingPackage(sourcePackage)
        }
        let destRoot = fm.temporaryDirectory
            .appendingPathComponent("PSLegacyStores-\(label)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: destRoot, withIntermediateDirectories: true)
        let dest = destRoot.appendingPathComponent(sourcePackage.lastPathComponent, isDirectory: true)
        try fm.copyItem(at: sourcePackage, to: dest)
        return storeURL(inPackage: dest)
    }

    static func openMigratedContainer(at storeURL: URL) throws -> ModelContainer {
        try AppModelContainer.make(at: storeURL)
    }

    // MARK: - Stable IDs for assertions (deterministic across regenerations)

    enum FixedIDs {
        static let user = AppIdentity.defaultUserId
        static let draftProfile = UUID(uuidString: "b3000003-0003-4000-8000-000000000001")!
        static let confirmedProfile = UUID(uuidString: "b3000004-0004-4000-8000-000000000001")!
        static let wearEvent = UUID(uuidString: "b3000007-0007-4000-8000-000000000001")!
        static let photoGarment = UUID(uuidString: "a1000001-0001-4000-8000-000000000001")!
        static let batch = UUID(uuidString: "b3000007-0007-4000-8000-000000000010")!
        static let pendingCapture = UUID(uuidString: "b3000007-0007-4000-8000-000000000011")!
        static let userPhotoPath = "user-photo:\(photoGarment.uuidString)"
    }

    // MARK: - Generators

    @MainActor
    static func generate(id: LegacyStoreFixtureID, at packageDirectory: URL) throws {
        switch id {
        case .row3LegacyDraftProfile:
            try generateRow3DraftProfile(at: packageDirectory)
        case .row4LegacyConfirmedProfile:
            try generateRow4ConfirmedProfile(at: packageDirectory)
        case .row7PendingCaptureBatch:
            try generateRow7PendingCaptureBatch(at: packageDirectory)
        case .seededWardrobe:
            try generateSeededWardrobe(at: packageDirectory)
        case .mainShapedV1_1:
            try generateMainShapedV1_1(at: packageDirectory)
        }
    }

    /// Write a V1 (09e292a-shaped) store with a draft profile only.
    @MainActor
    static func generateRow3DraftProfile(at packageDirectory: URL) throws {
        try writeV1Store(at: packageDirectory) { context in
            context.insert(UserEntity(id: FixedIDs.user))
            context.insert(
                StyleProfileEntity(
                    id: FixedIDs.draftProfile,
                    userId: FixedIDs.user,
                    version: 1,
                    profession: "Engineer",
                    summaryText: "Draft summary",
                    summaryUserOwned: true,
                    confirmedAt: nil,
                    seedSource: nil
                )
            )
        }
    }

    /// Write a V1 store with a confirmed profile (no garments).
    @MainActor
    static func generateRow4ConfirmedProfile(at packageDirectory: URL) throws {
        let confirmedAt = Date(timeIntervalSince1970: 1_725_000_000)
        try writeV1Store(at: packageDirectory) { context in
            context.insert(UserEntity(id: FixedIDs.user))
            context.insert(
                StyleProfileEntity(
                    id: FixedIDs.confirmedProfile,
                    userId: FixedIDs.user,
                    version: 2,
                    profession: "Engineer",
                    summaryText: "Confirmed summary",
                    summaryUserOwned: true,
                    confirmedAt: confirmedAt,
                    seedSource: "founder-seed"
                )
            )
        }
    }

    /// Write a V1 seeded wardrobe (+ wear + imagePath without GarmentImage row to exercise reconcile).
    @MainActor
    static func generateSeededWardrobe(at packageDirectory: URL) throws {
        try writeV1Store(at: packageDirectory) { context in
            context.insert(UserEntity(id: FixedIDs.user))
            let fixtures = FixtureWardrobeLoader.loadGarments()
            for stub in fixtures {
                let entity = StubEntityMapper.makeEntity(from: stub, userId: FixedIDs.user)
                if entity.id == FixedIDs.photoGarment {
                    entity.imagePath = FixedIDs.userPhotoPath
                }
                context.insert(entity)
            }
            for s in FixtureWardrobeLoader.loadSets() {
                context.insert(StubEntityMapper.makeSetEntity(from: s, userId: FixedIDs.user))
            }
            let wear = WearEventEntity(
                id: FixedIDs.wearEvent,
                userId: FixedIDs.user,
                wornOn: Date(timeIntervalSince1970: 1_725_100_000),
                garmentIds: [FixedIDs.photoGarment],
                sourceRaw: "MANUAL_CONFIRM"
            )
            context.insert(wear)
        }
    }

    /// Write a V1.1 (current-main) store with membership + query index rows.
    @MainActor
    static func generateMainShapedV1_1(at packageDirectory: URL) throws {
        try writeLegacyStore(
            versionedSchema: PersonalStylistSchemaV1_1.self,
            at: packageDirectory
        ) { context in
            context.insert(UserEntity(id: FixedIDs.user))
            let stub = FixtureWardrobeLoader.loadGarments().first!
            let entity = StubEntityMapper.makeEntity(from: stub, userId: FixedIDs.user)
            context.insert(entity)
            GarmentIndexSync.upsert(entity: entity, in: context)
            let wear = WearEventEntity(
                id: FixedIDs.wearEvent,
                userId: FixedIDs.user,
                wornOn: Date(timeIntervalSince1970: 1_725_100_000),
                garmentIds: [entity.id],
                sourceRaw: "MANUAL_CONFIRM"
            )
            context.insert(wear)
            WearMembershipSync.replace(event: wear, in: context)
        }
    }

    /// Write a V2 store with pending capture batch (PRD §3.1 row 7 structure).
    @MainActor
    static func generateRow7PendingCaptureBatch(at packageDirectory: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: packageDirectory.path) {
            try fm.removeItem(at: packageDirectory)
        }
        try fm.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        let url = storeURL(inPackage: packageDirectory)
        let container = try AppModelContainer.make(at: url)
        defer { /* container released at end of scope */ }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(UserEntity(id: FixedIDs.user))
        context.insert(
            StyleProfileEntity(
                id: FixedIDs.confirmedProfile,
                userId: FixedIDs.user,
                version: 1,
                confirmedAt: Date(timeIntervalSince1970: 1_725_000_000)
            )
        )
        let batch = CaptureBatchEntity(
            id: FixedIDs.batch,
            userId: FixedIDs.user,
            sourceRaw: "CAMERA",
            readingAllowed: false,
            readingDecidedAt: Date(timeIntervalSince1970: 1_725_200_000),
            policyVersionAtChoice: "test-fixture-policy",
            captureIds: [FixedIDs.pendingCapture],
            reviewCursor: 0
        )
        context.insert(batch)
        context.insert(
            PendingCaptureEntity(
                id: FixedIDs.pendingCapture,
                userId: FixedIDs.user,
                batchId: FixedIDs.batch,
                masterURI: "pending-captures/\(FixedIDs.pendingCapture.uuidString).jpg",
                imageStateRaw: "SAVED",
                analysisStateRaw: "NOT_REQUESTED",
                reviewStateRaw: "PENDING"
            )
        )
        try context.save()
    }

    @MainActor
    private static func writeV1Store(
        at packageDirectory: URL,
        populate: (ModelContext) throws -> Void
    ) throws {
        try writeLegacyStore(
            versionedSchema: PersonalStylistSchemaV1.self,
            at: packageDirectory,
            populate: populate
        )
    }

    @MainActor
    private static func writeLegacyStore(
        versionedSchema: any VersionedSchema.Type,
        at packageDirectory: URL,
        populate: (ModelContext) throws -> Void
    ) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: packageDirectory.path) {
            try fm.removeItem(at: packageDirectory)
        }
        try fm.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
        let url = storeURL(inPackage: packageDirectory)
        let container = try AppModelContainer.makeLegacyWriter(versionedSchema: versionedSchema, at: url)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try populate(context)
        try context.save()
    }
}

enum LegacyStoreFixtureError: Error, CustomStringConvertible {
    case missingPackage(URL)

    var description: String {
        switch self {
        case .missingPackage(let url):
            return "Missing legacy store package at \(url.path)"
        }
    }
}
