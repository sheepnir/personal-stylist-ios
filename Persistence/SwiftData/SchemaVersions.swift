import Foundation
import SwiftData

// MARK: - Schema inventory (#215)
//
// Historical baselines (entity graph only):
// - V1 (1.0.0) — commit `09e292a`: User, StyleProfile, Garment, GarmentImage,
//   GarmentSet, Outfit, OutfitAssignment, WearEvent, PreferenceRule.
//   No WearMembershipEntity, no GarmentQueryIndex.
// - V1.1 (1.1.0) — current main before onboarding (#214): V1 + WearMembershipEntity
//   + GarmentQueryIndex.
// - V2 (2.0.0) — onboarding shells (PRD §3.3) + nullable/defaulted fields (PRD §7).
//   D-72 adds optional `GarmentEntity.attributeSourceJSON` on the live V2 type.
//   A V2.1 VersionedSchema was not added: SwiftData hashes the shared @Model class,
//   so a same-graph stage throws "Duplicate version checksums across stages".
//
// Live `@Model` types live in DomainModels.swift (V2 shape). Lightweight stages add
// entities and optional attributes; VersionedSchema.models lists which types belong
// to each stamped version when writing fixtures.

enum PersonalStylistSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserEntity.self,
            StyleProfileEntity.self,
            GarmentEntity.self,
            GarmentImageEntity.self,
            GarmentSetEntity.self,
            OutfitEntity.self,
            OutfitAssignmentEntity.self,
            WearEventEntity.self,
            PreferenceRuleEntity.self,
        ]
    }
}

enum PersonalStylistSchemaV1_1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserEntity.self,
            StyleProfileEntity.self,
            GarmentEntity.self,
            GarmentImageEntity.self,
            GarmentSetEntity.self,
            OutfitEntity.self,
            OutfitAssignmentEntity.self,
            WearEventEntity.self,
            WearMembershipEntity.self,
            GarmentQueryIndex.self,
            PreferenceRuleEntity.self,
        ]
    }
}

enum PersonalStylistSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserEntity.self,
            StyleProfileEntity.self,
            GarmentEntity.self,
            GarmentImageEntity.self,
            GarmentSetEntity.self,
            OutfitEntity.self,
            OutfitAssignmentEntity.self,
            WearEventEntity.self,
            WearMembershipEntity.self,
            GarmentQueryIndex.self,
            PreferenceRuleEntity.self,
            OnboardingStateEntity.self,
            StyleProfileDraftEntity.self,
            PrivacyConsentEntity.self,
            CaptureBatchEntity.self,
            PendingCaptureEntity.self,
        ]
    }
}

// MARK: - Migration plan

enum PersonalStylistMigrationPlan: SchemaMigrationPlan {
    /// UserDefaults key: #121 pattern/surface backfill completed (or owned by →V2 migration).
    static let fixturePatternSurfaceBackfillKey = "migration.fixturePatternSurface.v1"

    /// Set in didMigrate →V2 so post-migration launches never re-order #121 against V2 incorrectly.
    static let schemaV2MigrationCompletedKey = "migration.schema.v2.completed"

    static var schemas: [any VersionedSchema.Type] {
        [
            PersonalStylistSchemaV1.self,
            PersonalStylistSchemaV1_1.self,
            PersonalStylistSchemaV2.self,
        ]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV1_1, migrateV1_1toV2]
    }

    /// Additive: WearMembershipEntity + GarmentQueryIndex (#164 / #167).
    static let migrateV1toV1_1 = MigrationStage.lightweight(
        fromVersion: PersonalStylistSchemaV1.self,
        toVersion: PersonalStylistSchemaV1_1.self
    )

    /// Onboarding entity shells + PRD §7 fields. #121 backfill runs in willMigrate
    /// (pre-V2 store only); didMigrate marks both backfill and V2-complete flags.
    static let migrateV1_1toV2 = MigrationStage.custom(
        fromVersion: PersonalStylistSchemaV1_1.self,
        toVersion: PersonalStylistSchemaV2.self,
        willMigrate: { context in
            FixturePatternSurfaceBackfill.runIfNeeded(in: context, defaults: .standard)
        },
        didMigrate: { context in
            GarmentPhotoReferenceReconciliation.reconcile(in: context)
            try? context.save()
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: fixturePatternSurfaceBackfillKey)
            defaults.set(true, forKey: schemaV2MigrationCompletedKey)
        }
    )
}

// MARK: - #121 backfill (shared by migration willMigrate + store seed path)

enum FixturePatternSurfaceBackfill {
    /// Narrow repair: READY fixture-id rows still missing pattern/surface.
    /// Callers gate with UserDefaults; →V2 willMigrate owns the pre-V2 pass.
    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults) {
        guard defaults.bool(forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey) == false else {
            return
        }
        // Never run against a store that already completed →V2 (AC #215).
        if defaults.bool(forKey: PersonalStylistMigrationPlan.schemaV2MigrationCompletedKey) {
            defaults.set(true, forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey)
            return
        }

        let fixturesById = Dictionary(
            uniqueKeysWithValues: FixtureWardrobeLoader.loadGarments().map { ($0.id, $0) }
        )
        guard !fixturesById.isEmpty else {
            defaults.set(true, forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey)
            return
        }

        let readyRaw = StubReadiness.ready.rawValue
        let rows = (try? context.fetch(FetchDescriptor<GarmentEntity>())) ?? []
        var anyChanged = false
        for entity in rows {
            guard let fixture = fixturesById[entity.id] else { continue }
            guard entity.readinessRaw == readyRaw else { continue }
            var entityChanged = false
            if entity.pattern == nil, let pattern = fixture.pattern {
                entity.pattern = pattern
                entityChanged = true
            }
            if entity.surface == nil, let surface = fixture.surface {
                entity.surface = surface
                entityChanged = true
            }
            if entityChanged {
                entity.updatedAt = Date()
                anyChanged = true
            }
        }
        if anyChanged {
            try? context.save()
        }
        defaults.set(true, forKey: PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey)
    }
}

// MARK: - imagePath ↔ GarmentImageEntity contract (#215)
//
// Single documented representation:
// - `GarmentEntity.imagePath` is the stable UI/DTO reference consumed by StubGarment and
//   `UserGarmentPhotoStore` (`user-photo:{uuid}` → Documents/GarmentPhotos/{uuid}.jpg,
//   or bundled fixture relative paths). Existing installs keep reading this string after
//   migration with no path rewrite.
// - `GarmentImageEntity` is the relational photo row. For the primary image,
//   `originalURI` mirrors `imagePath` (identical string). `processedURI` is optional.
// - Capture work (#191) extends GarmentImageEntity; do not drop `imagePath` until all
//   readers use the relational row exclusively.
//
// Reconciliation on →V2: if `imagePath` is set and there is no primary GarmentImageEntity,
// insert one with `originalURI = imagePath` so Documents/GarmentPhotos access stays valid.

enum GarmentPhotoReferenceReconciliation {
    static func reconcile(in context: ModelContext) {
        let garments = (try? context.fetch(FetchDescriptor<GarmentEntity>())) ?? []
        for garment in garments {
            guard let path = garment.imagePath, !path.isEmpty else { continue }
            let hasPrimary = garment.images.contains { $0.isPrimary }
            if hasPrimary { continue }
            if garment.images.contains(where: { $0.originalURI == path }) { continue }
            let image = GarmentImageEntity(
                userId: garment.userId,
                originalURI: path,
                processedURI: nil,
                isPrimary: true,
                garment: garment
            )
            context.insert(image)
        }
    }
}
