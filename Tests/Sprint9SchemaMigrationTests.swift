import XCTest
import SwiftData
@testable import PersonalStylist

/// Sprint 9 (#119, ADR-0004) — a populated Sprint 8-shaped V2 store opens as V3 with every
/// row, id, price, relationship and photo reference unchanged, and new gallery rows survive
/// further relaunches. Synthetic fixture data only.
final class Sprint9SchemaMigrationTests: XCTestCase {
    private typealias IDs = LegacyStoreFixtures.FixedIDs

    func testV3AddsOnlyTheWearingPhotoEntity() {
        let v2 = Set(PersonalStylistSchemaV2.models.map { String(describing: $0) })
        let v3 = Set(PersonalStylistSchemaV3.models.map { String(describing: $0) })
        XCTAssertEqual(v3.subtracting(v2), ["WearingPhotoEntity"])
        XCTAssertTrue(v2.isSubset(of: v3))
        XCTAssertEqual(PersonalStylistSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(PersonalStylistMigrationPlan.schemas.count, 4)
        XCTAssertEqual(PersonalStylistMigrationPlan.stages.count, 3)
        XCTAssertTrue(AppModelContainer.schema.entities.contains { $0.name == "WearingPhotoEntity" })
    }

    @MainActor
    func testPopulatedSprint8StoreUpgradesWithoutRewriting() throws {
        let working = try TestLegacyStoreFixtures.makeWorkingPackage(id: .sprint8PopulatedV2)
        defer { try? FileManager.default.removeItem(at: working.cleanupRoot) }

        // Snapshot through a V2-only reader before the upgrade.
        let before: Snapshot
        do {
            let reader = try AppModelContainer.makeLegacyWriter(
                versionedSchema: PersonalStylistSchemaV2.self,
                at: working.storeURL
            )
            before = try Snapshot(context: ModelContext(reader))
        }
        XCTAssertGreaterThan(before.garments.count, 1)
        XCTAssertEqual(before.wears.count, 2)

        for pass in 1...3 {
            let container = try LegacyStoreFixtures.openMigratedContainer(at: working.storeURL)
            let context = ModelContext(container)
            let after = try Snapshot(context: context)
            XCTAssertEqual(after, before, "semantic rows unchanged — pass \(pass)")

            let allGarments = try context.fetch(FetchDescriptor<GarmentEntity>())
            let photo = try XCTUnwrap(allGarments.first(where: { $0.id == IDs.photoGarment }))
            XCTAssertEqual(photo.imagePath, IDs.userPhotoPath)
            XCTAssertEqual(photo.purchasePrice, IDs.sprint8Price)
            XCTAssertEqual(photo.purchaseCurrency, "EUR")
            XCTAssertEqual(photo.images.first(where: { $0.isPrimary })?.originalURI, IDs.userPhotoPath)
            let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<StyleProfileEntity>()).first)
            XCTAssertEqual(profile.id, IDs.sprint8Profile)
            XCTAssertEqual(profile.version, 3, "migration never bumps the profile version")

            let gallery = try context.fetch(FetchDescriptor<WearingPhotoEntity>())
            if pass == 1 {
                XCTAssertTrue(gallery.isEmpty, "upgrade creates no gallery rows")
                context.insert(
                    WearingPhotoEntity(
                        garmentId: IDs.photoGarment,
                        displayFileId: UUID(),
                        sourceFileId: UUID(),
                        addedAt: Date(timeIntervalSince1970: 1_760_000_000),
                        sourceRaw: WearingPhotoSource.library.rawValue
                    )
                )
                try context.save()
            } else {
                XCTAssertEqual(gallery.count, 1, "new gallery row survives relaunch — pass \(pass)")
                XCTAssertEqual(gallery.first?.garmentId, IDs.photoGarment)
            }
            _ = container
        }
    }

    /// Order-independent semantic view of the rows the upgrade must preserve.
    private struct Snapshot: Equatable {
        struct Garment: Equatable {
            var id: UUID, name: String, slot: String, readiness: String, availability: String
            var imagePath: String?, primaryURI: String?, price: Decimal?, currency: String?
            var setId: UUID?, createdAt: Date
        }
        struct Wear: Equatable {
            var id: UUID, wornOn: Date, garmentIds: [UUID], sourceOutfitId: UUID?, voidedAt: Date?
        }
        var garments: [Garment]
        var wears: [Wear]
        var memberships: [String]
        var sets: [String]
        var outfits: [String]
        var profiles: [String]
        var indexes: Int

        init(context: ModelContext) throws {
            var garmentRows: [Garment] = []
            for entity in try context.fetch(FetchDescriptor<GarmentEntity>()) {
                let primary = entity.images.first(where: { image in image.isPrimary })
                garmentRows.append(
                    Garment(
                        id: entity.id, name: entity.displayName, slot: entity.slotRaw,
                        readiness: entity.readinessRaw, availability: entity.availability,
                        imagePath: entity.imagePath, primaryURI: primary?.originalURI,
                        price: entity.purchasePrice, currency: entity.purchaseCurrency,
                        setId: entity.setId, createdAt: entity.createdAt
                    )
                )
            }
            garments = garmentRows.sorted { $0.id.uuidString < $1.id.uuidString }
            var wearRows: [Wear] = []
            for event in try context.fetch(FetchDescriptor<WearEventEntity>()) {
                wearRows.append(
                    Wear(
                        id: event.id, wornOn: event.wornOn, garmentIds: event.garmentIds,
                        sourceOutfitId: event.sourceOutfitId, voidedAt: event.voidedAt
                    )
                )
            }
            wears = wearRows.sorted { $0.id.uuidString < $1.id.uuidString }
            memberships = try context.fetch(FetchDescriptor<WearMembershipEntity>())
                .map { "\($0.eventId)|\($0.garmentId)|\($0.voided)" }
                .sorted()
            sets = try context.fetch(FetchDescriptor<GarmentSetEntity>())
                .map { "\($0.id)|\($0.displayName)|\($0.keepTogether)|\($0.memberGarmentIds)" }
                .sorted()
            outfits = try context.fetch(FetchDescriptor<OutfitEntity>())
                .map { outfit in
                    let slots = outfit.assignments
                        .map { "\($0.slotRaw):\($0.garmentId?.uuidString ?? "-"):\($0.isAnchor)" }
                        .sorted()
                    return "\(outfit.id)|\(outfit.rationaleSummary)|\(slots)"
                }
                .sorted()
            profiles = try context.fetch(FetchDescriptor<StyleProfileEntity>())
                .map { "\($0.id)|\($0.version)|\($0.profession ?? "")|\(String(describing: $0.confirmedAt))" }
                .sorted()
            indexes = try context.fetchCount(FetchDescriptor<GarmentQueryIndex>())
        }
    }
}
