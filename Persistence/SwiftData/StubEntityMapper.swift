import Foundation

enum StubEntityMapper {
    static func stub(from entity: GarmentEntity) -> StubGarment {
        let slot = StubSlot(rawValue: entity.slotRaw) ?? .top
        let readiness = StubReadiness(rawValue: entity.readinessRaw) ?? .draft
        let color: StubColorPrimary? = {
            if entity.colorFamily == nil, entity.colorHex == nil, entity.colorName == nil { return nil }
            return StubColorPrimary(family: entity.colorFamily, hex: entity.colorHex, name: entity.colorName)
        }()
        return StubGarment(
            id: entity.id,
            displayName: entity.displayName,
            slot: slot,
            readiness: readiness,
            availability: entity.availability,
            colorPrimary: color,
            pattern: entity.pattern,
            surface: entity.surface,
            imagePath: entity.imagePath,
            formality: entity.formality,
            warmth: entity.warmth,
            setId: entity.setId,
            keepTogether: nil,
            lastWornOn: entity.lastWornOn,
            daysSinceIntake: entity.daysSinceIntake,
            createdAt: entity.createdAt,
            displayNameSource: entity.displayNameSource,
            purchasePrice: entity.purchasePrice,
            purchaseCurrency: entity.purchaseCurrency,
            purchaseDate: entity.purchaseDate,
            priorWearBucket: entity.priorWearBucket,
            priorWearEstimate: entity.priorWearEstimate,
            attributeSource: decodeAttributeSource(entity.attributeSourceJSON)
        )
    }

    static func apply(_ stub: StubGarment, to entity: GarmentEntity) {
        entity.displayName = stub.displayName
        entity.slotRaw = stub.slot.rawValue
        entity.readinessRaw = stub.readiness.rawValue
        entity.availability = stub.availability
        entity.colorFamily = stub.colorPrimary?.family
        entity.colorHex = stub.colorPrimary?.hex
        entity.colorName = stub.colorPrimary?.name
        entity.pattern = stub.pattern
        entity.surface = stub.surface
        entity.imagePath = stub.imagePath
        entity.formality = stub.formality
        entity.warmth = stub.warmth
        entity.setId = stub.setId
        entity.lastWornOn = stub.lastWornOn
        entity.daysSinceIntake = stub.daysSinceIntake
        entity.displayNameSource = stub.displayNameSource
        let price = StubGarment.persistedPurchasePrice(stub.purchasePrice)
        entity.purchasePrice = price
        entity.purchaseCurrency = price == nil ? nil : stub.purchaseCurrency
        entity.purchaseDate = stub.purchaseDate
        entity.priorWearBucket = stub.priorWearBucket
        entity.priorWearEstimate = stub.priorWearEstimate
        entity.attributeSourceJSON = encodeAttributeSource(stub.attributeSource)
        entity.updatedAt = Date()
    }

    static func makeEntity(from stub: StubGarment, userId: UUID = AppIdentity.defaultUserId) -> GarmentEntity {
        GarmentEntity(
            id: stub.id,
            userId: userId,
            displayName: stub.displayName,
            displayNameSource: stub.displayNameSource,
            slotRaw: stub.slot.rawValue,
            setId: stub.setId,
            readinessRaw: stub.readiness.rawValue,
            colorFamily: stub.colorPrimary?.family,
            colorHex: stub.colorPrimary?.hex,
            colorName: stub.colorPrimary?.name,
            pattern: stub.pattern,
            surface: stub.surface,
            formality: stub.formality,
            warmth: stub.warmth,
            availability: stub.availability,
            purchasePrice: StubGarment.persistedPurchasePrice(stub.purchasePrice),
            purchaseCurrency: StubGarment.persistedPurchasePrice(stub.purchasePrice) == nil ? nil : stub.purchaseCurrency,
            purchaseDate: stub.purchaseDate,
            priorWearEstimate: stub.priorWearEstimate,
            priorWearBucket: stub.priorWearBucket,
            imagePath: stub.imagePath,
            lastWornOn: stub.lastWornOn,
            daysSinceIntake: stub.daysSinceIntake,
            attributeSourceJSON: encodeAttributeSource(stub.attributeSource),
            createdAt: stub.intakeSortDate(referenceDate: Date())
        )
    }

    static func stub(from entity: StyleProfileEntity) -> StubStyleProfile {
        StubStyleProfile(
            id: entity.id,
            age: entity.age,
            profession: entity.profession,
            workEnvironment: entity.workEnvironment,
            workEnvironmentLabel: entity.workEnvironmentLabel,
            typicalWeekNotes: entity.typicalWeekNotes,
            goals: entity.goals,
            constraintsNotes: entity.constraintsNotes,
            experimentationLevel: entity.experimentationLevel,
            summary: entity.summaryText,
            summaryUserOwned: entity.summaryUserOwned,
            version: entity.version,
            confirmedAt: entity.confirmedAt,
            seedSource: entity.seedSource
        )
    }

    static func apply(_ stub: StubStyleProfile, to entity: StyleProfileEntity) {
        entity.age = stub.age
        entity.profession = stub.profession
        entity.workEnvironment = stub.workEnvironment
        entity.workEnvironmentLabel = stub.workEnvironmentLabel
        entity.typicalWeekNotes = stub.typicalWeekNotes
        entity.goals = stub.goals
        entity.constraintsNotes = stub.constraintsNotes
        entity.experimentationLevel = stub.experimentationLevel
        entity.summaryText = stub.summary
        entity.summaryUserOwned = stub.summaryUserOwned
        entity.version = stub.version
        entity.confirmedAt = stub.confirmedAt
        entity.seedSource = stub.seedSource
        entity.updatedAt = Date()
    }

    static func makeEntity(from stub: StubStyleProfile, userId: UUID = AppIdentity.defaultUserId) -> StyleProfileEntity {
        StyleProfileEntity(
            id: stub.id,
            userId: userId,
            version: stub.version,
            age: stub.age,
            profession: stub.profession,
            workEnvironment: stub.workEnvironment,
            workEnvironmentLabel: stub.workEnvironmentLabel,
            typicalWeekNotes: stub.typicalWeekNotes,
            goals: stub.goals,
            constraintsNotes: stub.constraintsNotes,
            experimentationLevel: stub.experimentationLevel,
            summaryText: stub.summary,
            summaryUserOwned: stub.summaryUserOwned,
            confirmedAt: stub.confirmedAt,
            seedSource: stub.seedSource
        )
    }

    static func stub(from entity: OutfitEntity) -> StubOutfit {
        let assignments = entity.assignments.map { a in
            StubOutfitAssignment(
                id: a.id,
                slot: StubSlot(rawValue: a.slotRaw) ?? .top,
                garmentId: a.garmentId,
                gapReason: a.gapReason,
                isAnchor: a.isAnchor,
                isLocked: a.isLocked
            )
        }
        return StubOutfit(
            id: entity.id,
            assignments: assignments,
            rationaleSummary: entity.rationaleSummary,
            offlineCached: entity.offlineCached
        )
    }

    static func makeEntity(from stub: StubOutfit, userId: UUID = AppIdentity.defaultUserId) -> OutfitEntity {
        let outfit = OutfitEntity(
            id: stub.id,
            userId: userId,
            sessionId: UUID(),
            rationaleSummary: stub.rationaleSummary,
            offlineCached: stub.offlineCached,
            statusRaw: "SUGGESTED"
        )
        outfit.assignments = stub.assignments.map { a in
            OutfitAssignmentEntity(
                id: a.id,
                userId: userId,
                slotRaw: a.slot.rawValue,
                garmentId: a.garmentId,
                isAnchor: a.isAnchor,
                isLocked: a.isLocked,
                gapReason: a.gapReason,
                outfit: outfit
            )
        }
        return outfit
    }

    static func stub(from entity: WearEventEntity) -> StubWearEvent {
        StubWearEvent(
            id: entity.id,
            garmentIds: entity.garmentIds,
            wornOn: entity.wornOn,
            voidedAt: entity.voidedAt,
            sourceOutfitId: entity.sourceOutfitId
        )
    }

    static func makeEntity(from stub: StubWearEvent, userId: UUID = AppIdentity.defaultUserId) -> WearEventEntity {
        WearEventEntity(
            id: stub.id,
            userId: userId,
            wornOn: stub.wornOn,
            garmentIds: stub.garmentIds,
            sourceOutfitId: stub.sourceOutfitId,
            sourceRaw: stub.sourceOutfitId == nil ? "MANUAL_CONFIRM" : "OUTFIT_CONFIRM",
            voidedAt: stub.voidedAt
        )
    }

    static func makeSetEntity(from stub: StubSet, userId: UUID = AppIdentity.defaultUserId) -> GarmentSetEntity {
        GarmentSetEntity(
            id: stub.id,
            userId: userId,
            displayName: stub.displayName,
            keepTogether: stub.keepTogether,
            memberGarmentIds: stub.memberGarmentIds,
            notes: stub.notes
        )
    }

    static func stub(from entity: GarmentSetEntity) -> StubSet {
        StubSet(
            id: entity.id,
            displayName: entity.displayName,
            keepTogether: entity.keepTogether,
            memberGarmentIds: entity.memberGarmentIds,
            notes: entity.notes
        )
    }

    private static func encodeAttributeSource(_ source: [String: String]) -> Data? {
        guard !source.isEmpty else { return nil }
        return try? JSONEncoder().encode(source)
    }

    private static func decodeAttributeSource(_ data: Data?) -> [String: String] {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
