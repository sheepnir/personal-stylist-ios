import Foundation
import SwiftData

// MARK: - User

@Model
final class UserEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var locale: String
    var currency: String

    init(
        id: UUID = AppIdentity.defaultUserId,
        createdAt: Date = Date(),
        locale: String = AppIdentity.defaultLocale,
        currency: String = AppIdentity.defaultCurrency
    ) {
        self.id = id
        self.createdAt = createdAt
        self.locale = locale
        self.currency = currency
    }
}

// MARK: - StyleProfile (versioned)

@Model
final class StyleProfileEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var version: Int
    var age: Int?
    var profession: String?
    var workEnvironment: String?
    var workEnvironmentLabel: String?
    var typicalWeekNotes: String?
    var goalsJSON: Data?
    var constraintsNotes: String?
    var experimentationLevel: Int?
    var summaryText: String?
    var summaryUserOwned: Bool
    /// PRD §7 — TEMPLATE | MODEL | USER (nullable additive).
    var summarySourceRaw: String?
    /// Canonical answer keys at confirmation (PRD §7); absent = unknown.
    var answersJSON: Data?
    var confirmedAt: Date?
    var seedSource: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        version: Int = 1,
        age: Int? = nil,
        profession: String? = nil,
        workEnvironment: String? = nil,
        workEnvironmentLabel: String? = nil,
        typicalWeekNotes: String? = nil,
        goals: [String] = [],
        constraintsNotes: String? = nil,
        experimentationLevel: Int? = nil,
        summaryText: String? = nil,
        summaryUserOwned: Bool = false,
        summarySourceRaw: String? = nil,
        answersJSON: Data? = nil,
        confirmedAt: Date? = nil,
        seedSource: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.version = version
        self.age = age
        self.profession = profession
        self.workEnvironment = workEnvironment
        self.workEnvironmentLabel = workEnvironmentLabel
        self.typicalWeekNotes = typicalWeekNotes
        self.goalsJSON = try? JSONEncoder().encode(goals)
        self.constraintsNotes = constraintsNotes
        self.experimentationLevel = experimentationLevel
        self.summaryText = summaryText
        self.summaryUserOwned = summaryUserOwned
        self.summarySourceRaw = summarySourceRaw
        self.answersJSON = answersJSON
        self.confirmedAt = confirmedAt
        self.seedSource = seedSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var goals: [String] {
        get {
            guard let goalsJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: goalsJSON) else { return [] }
            return decoded
        }
        set { goalsJSON = try? JSONEncoder().encode(newValue) }
    }

    var isDraft: Bool { confirmedAt == nil }
}

// MARK: - Garment (drafts / readiness D-23 / D-31)

@Model
final class GarmentEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var displayName: String
    var displayNameSource: String // USER | DERIVED
    var slotRaw: String
    var category: String?
    var setId: UUID?
    var readinessRaw: String // DRAFT | READY (stored; may also be derived at map time)
    var colorFamily: String?
    var colorHex: String?
    var colorName: String?
    var pattern: String?
    var materialsJSON: Data?
    var surface: String?
    var formality: Int?
    var warmth: Int?
    var seasonsJSON: Data?
    var fit: String?
    var availability: String
    var availableAgainOn: Date?
    var isFavorite: Bool
    var wantToWearMore: Bool
    var purchasePrice: Decimal?
    var purchaseCurrency: String?
    var purchaseDate: Date?
    var priorWearEstimate: Int?
    var priorWearBucket: String?
    /// Stable UI/DTO photo key — see `GarmentPhotoReferenceReconciliation` (#215).
    var imagePath: String?
    var notes: String?
    var lastWornOn: String?
    var daysSinceIntake: Int?
    /// PRD §7 / D-66: provenance to PendingCapture; slot stays non-null.
    var captureId: UUID?
    /// CAMERA | LIBRARY | MANUAL
    var captureSourceRaw: String?
    var attributionWarningsJSON: Data?
    /// D-72 — field → USER|MODEL JSON. Optional additive on the live V2 type.
    var attributeSourceJSON: Data?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \GarmentImageEntity.garment)
    var images: [GarmentImageEntity]

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        displayName: String,
        displayNameSource: String = "DERIVED",
        slotRaw: String,
        category: String? = nil,
        setId: UUID? = nil,
        readinessRaw: String,
        colorFamily: String? = nil,
        colorHex: String? = nil,
        colorName: String? = nil,
        pattern: String? = nil,
        materials: [String] = [],
        surface: String? = nil,
        formality: Int? = nil,
        warmth: Int? = nil,
        seasons: [String] = [],
        fit: String? = nil,
        availability: String = "AVAILABLE",
        availableAgainOn: Date? = nil,
        isFavorite: Bool = false,
        wantToWearMore: Bool = false,
        purchasePrice: Decimal? = nil,
        purchaseCurrency: String? = nil,
        purchaseDate: Date? = nil,
        priorWearEstimate: Int? = nil,
        priorWearBucket: String? = nil,
        imagePath: String? = nil,
        notes: String? = nil,
        lastWornOn: String? = nil,
        daysSinceIntake: Int? = nil,
        captureId: UUID? = nil,
        captureSourceRaw: String? = nil,
        attributionWarnings: [String] = [],
        attributeSourceJSON: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        images: [GarmentImageEntity] = []
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.displayNameSource = displayNameSource
        self.slotRaw = slotRaw
        self.category = category
        self.setId = setId
        self.readinessRaw = readinessRaw
        self.colorFamily = colorFamily
        self.colorHex = colorHex
        self.colorName = colorName
        self.pattern = pattern
        self.materialsJSON = try? JSONEncoder().encode(materials)
        self.surface = surface
        self.formality = formality
        self.warmth = warmth
        self.seasonsJSON = try? JSONEncoder().encode(seasons)
        self.fit = fit
        self.availability = availability
        self.availableAgainOn = availableAgainOn
        self.isFavorite = isFavorite
        self.wantToWearMore = wantToWearMore
        self.purchasePrice = purchasePrice
        self.purchaseCurrency = purchaseCurrency
        self.purchaseDate = purchaseDate
        self.priorWearEstimate = priorWearEstimate
        self.priorWearBucket = priorWearBucket
        self.imagePath = imagePath
        self.notes = notes
        self.lastWornOn = lastWornOn
        self.daysSinceIntake = daysSinceIntake
        self.captureId = captureId
        self.captureSourceRaw = captureSourceRaw
        self.attributionWarningsJSON = try? JSONEncoder().encode(attributionWarnings)
        self.attributeSourceJSON = attributeSourceJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.images = images
    }

    /// D-23 / D-31: READY iff core readiness fields are present.
    var derivedReadiness: String {
        if colorFamily != nil || colorHex != nil || colorName != nil,
           formality != nil,
           warmth != nil {
            // Pattern/surface may be sparse in fixtures; treat stored READY as authoritative when set.
            return readinessRaw
        }
        if readinessRaw == "READY",
           (colorFamily != nil || colorHex != nil || colorName != nil),
           formality != nil,
           warmth != nil {
            return "READY"
        }
        return readinessRaw == "READY" ? "READY" : "DRAFT"
    }
}

@Model
final class GarmentImageEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    /// Mirrors `GarmentEntity.imagePath` for the primary photo (#215).
    var originalURI: String
    var processedURI: String?
    var isPrimary: Bool
    var width: Int?
    var height: Int?
    /// PRD §7 — MASKED | CROPPED | FAILED
    var processingResultRaw: String?
    var maskCoverage: Float?
    var imageRevision: Int
    var createdAt: Date
    var garment: GarmentEntity?

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        originalURI: String,
        processedURI: String? = nil,
        isPrimary: Bool = true,
        width: Int? = nil,
        height: Int? = nil,
        processingResultRaw: String? = nil,
        maskCoverage: Float? = nil,
        imageRevision: Int = 1,
        createdAt: Date = Date(),
        garment: GarmentEntity? = nil
    ) {
        self.id = id
        self.userId = userId
        self.originalURI = originalURI
        self.processedURI = processedURI
        self.isPrimary = isPrimary
        self.width = width
        self.height = height
        self.processingResultRaw = processingResultRaw
        self.maskCoverage = maskCoverage
        self.imageRevision = imageRevision
        self.createdAt = createdAt
        self.garment = garment
    }
}

// MARK: - GarmentSet (keepTogether D-22)

@Model
final class GarmentSetEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var displayName: String
    var keepTogether: Bool
    var memberGarmentIdsData: Data
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        displayName: String,
        keepTogether: Bool,
        memberGarmentIds: [UUID] = [],
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.keepTogether = keepTogether
        self.memberGarmentIdsData = UUIDListCodec.encode(memberGarmentIds)
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var memberGarmentIds: [UUID] {
        get { UUIDListCodec.decode(memberGarmentIdsData) }
        set { memberGarmentIdsData = UUIDListCodec.encode(newValue) }
    }
}

// MARK: - Outfit + assignments

@Model
final class OutfitEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var sessionId: UUID
    var rationaleSummary: String
    var offlineCached: Bool
    var statusRaw: String
    var boldnessRaw: String?
    var supersedesOutfitId: UUID?
    var contextJSON: Data?
    var generationJSON: Data?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \OutfitAssignmentEntity.outfit)
    var assignments: [OutfitAssignmentEntity]

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        sessionId: UUID = UUID(),
        rationaleSummary: String = "",
        offlineCached: Bool = false,
        statusRaw: String = "SUGGESTED",
        boldnessRaw: String? = nil,
        supersedesOutfitId: UUID? = nil,
        contextJSON: Data? = nil,
        generationJSON: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        assignments: [OutfitAssignmentEntity] = []
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.rationaleSummary = rationaleSummary
        self.offlineCached = offlineCached
        self.statusRaw = statusRaw
        self.boldnessRaw = boldnessRaw
        self.supersedesOutfitId = supersedesOutfitId
        self.contextJSON = contextJSON
        self.generationJSON = generationJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.assignments = assignments
    }
}

@Model
final class OutfitAssignmentEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var slotRaw: String
    var garmentId: UUID?
    var isAnchor: Bool
    var isLocked: Bool
    var gapReason: String?
    var outfit: OutfitEntity?

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        slotRaw: String,
        garmentId: UUID? = nil,
        isAnchor: Bool = false,
        isLocked: Bool = false,
        gapReason: String? = nil,
        outfit: OutfitEntity? = nil
    ) {
        self.id = id
        self.userId = userId
        self.slotRaw = slotRaw
        self.garmentId = garmentId
        self.isAnchor = isAnchor
        self.isLocked = isLocked
        self.gapReason = gapReason
        self.outfit = outfit
    }
}

// MARK: - WearEvent

@Model
final class WearEventEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var wornOn: Date
    var garmentIdsData: Data
    var sourceOutfitId: UUID?
    var sessionId: UUID?
    var selectedAt: Date?
    var sourceRaw: String
    var voidedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        wornOn: Date = Date(),
        garmentIds: [UUID] = [],
        sourceOutfitId: UUID? = nil,
        sessionId: UUID? = nil,
        selectedAt: Date? = nil,
        sourceRaw: String = "OUTFIT_CONFIRM",
        voidedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.wornOn = wornOn
        self.garmentIdsData = UUIDListCodec.encode(garmentIds)
        self.sourceOutfitId = sourceOutfitId
        self.sessionId = sessionId
        self.selectedAt = selectedAt
        self.sourceRaw = sourceRaw
        self.voidedAt = voidedAt
        self.createdAt = createdAt
    }

    var garmentIds: [UUID] {
        get { UUIDListCodec.decode(garmentIdsData) }
        set { garmentIdsData = UUIDListCodec.encode(newValue) }
    }
}

// MARK: - PreferenceRule (schema complete; unused by demo UI yet)

@Model
final class PreferenceRuleEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var kindRaw: String
    var polarityRaw: String
    var subjectJSON: Data?
    var scopeRaw: String
    var provenanceRaw: String
    var supportingSignals: Int
    var active: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        kindRaw: String,
        polarityRaw: String,
        subjectJSON: Data? = nil,
        scopeRaw: String = "ALWAYS",
        provenanceRaw: String = "STATED",
        supportingSignals: Int = 0,
        active: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.kindRaw = kindRaw
        self.polarityRaw = polarityRaw
        self.subjectJSON = subjectJSON
        self.scopeRaw = scopeRaw
        self.provenanceRaw = provenanceRaw
        self.supportingSignals = supportingSignals
        self.active = active
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Compound query indexes (iOS 17 stand-in for SwiftData `#Index`, #167)
//
// `#Index` needs iOS 18. The deployment floor stays iOS 17 (VF-09), so each common
// filter is a unique string that SQLite indexes: userId + column + garment id.

enum GarmentIndexKey {
    static func userName(_ userId: UUID, name: String, id: UUID) -> String {
        "\(userId.uuidString.lowercased())|\(name.lowercased())|\(id.uuidString.lowercased())"
    }

    static func userSlot(_ userId: UUID, slot: String, id: UUID) -> String {
        "\(userId.uuidString.lowercased())|\(slot)|\(id.uuidString.lowercased())"
    }

    static func userAvailability(_ userId: UUID, availability: String, id: UUID) -> String {
        "\(userId.uuidString.lowercased())|\(availability)|\(id.uuidString.lowercased())"
    }

    static func userCreated(_ userId: UUID, createdAt: Date, id: UUID) -> String {
        let millis = String(format: "%013lld", Int64(createdAt.timeIntervalSince1970 * 1000))
        return "\(userId.uuidString.lowercased())|\(millis)|\(id.uuidString.lowercased())"
    }
}

@Model
final class GarmentQueryIndex {
    @Attribute(.unique) var garmentId: UUID
    var userId: UUID
    /// (userId, displayName, id)
    @Attribute(.unique) var idxUserName: String
    /// (userId, slot, id)
    @Attribute(.unique) var idxUserSlot: String
    /// (userId, availability, id)
    @Attribute(.unique) var idxUserAvailability: String
    /// (userId, createdAt, id)
    @Attribute(.unique) var idxUserCreated: String

    init(
        garmentId: UUID,
        userId: UUID,
        displayName: String,
        slotRaw: String,
        availability: String,
        createdAt: Date
    ) {
        self.garmentId = garmentId
        self.userId = userId
        self.idxUserName = GarmentIndexKey.userName(userId, name: displayName, id: garmentId)
        self.idxUserSlot = GarmentIndexKey.userSlot(userId, slot: slotRaw, id: garmentId)
        self.idxUserAvailability = GarmentIndexKey.userAvailability(userId, availability: availability, id: garmentId)
        self.idxUserCreated = GarmentIndexKey.userCreated(userId, createdAt: createdAt, id: garmentId)
    }
}

enum GarmentIndexSync {
    static func upsert(entity: GarmentEntity, in context: ModelContext) {
        let id = entity.id
        let existing = FetchDescriptor<GarmentQueryIndex>(predicate: #Predicate { $0.garmentId == id })
        if let row = try? context.fetch(existing).first {
            context.delete(row)
        }
        context.insert(
            GarmentQueryIndex(
                garmentId: entity.id,
                userId: entity.userId,
                displayName: entity.displayName,
                slotRaw: entity.slotRaw,
                availability: entity.availability,
                createdAt: entity.createdAt
            )
        )
    }
}

/// One row per garment on a wear event. Counts and last-worn do not decode JSON id lists (#164).
@Model
final class WearMembershipEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var eventId: UUID
    var garmentId: UUID
    var wornOn: Date
    var voided: Bool

    init(
        id: UUID = UUID(),
        userId: UUID,
        eventId: UUID,
        garmentId: UUID,
        wornOn: Date,
        voided: Bool
    ) {
        self.id = id
        self.userId = userId
        self.eventId = eventId
        self.garmentId = garmentId
        self.wornOn = wornOn
        self.voided = voided
    }
}

enum WearMembershipSync {
    static func replace(event: WearEventEntity, in context: ModelContext) {
        let eventId = event.id
        let existing = FetchDescriptor<WearMembershipEntity>(predicate: #Predicate { $0.eventId == eventId })
        for row in (try? context.fetch(existing)) ?? [] {
            context.delete(row)
        }
        let voided = event.voidedAt != nil
        for garmentId in event.garmentIds {
            context.insert(
                WearMembershipEntity(
                    userId: event.userId,
                    eventId: event.id,
                    garmentId: garmentId,
                    wornOn: event.wornOn,
                    voided: voided
                )
            )
        }
    }
}

// MARK: - Onboarding shells (PRD §3.3) — structure only; no first-run UI (D-58/59/60)

@Model
final class OnboardingStateEntity {
    @Attribute(.unique) var userId: UUID
    /// WELCOME | PRIVACY | ABOUT_1..ABOUT_6 | SUMMARY | CAPTURE_INTRO | CAPTURING | REVIEWING | COVERAGE | DONE
    var stepRaw: String
    var startedAt: Date
    var welcomeSeenAt: Date?
    var captureIntroSeenAt: Date?
    var profileCompletedAt: Date?
    var captureSkippedAt: Date?
    var captureCompletedAt: Date?
    var firstOutfitOfferedAt: Date?
    var lastActivityAt: Date
    var demoMode: Bool

    init(
        userId: UUID = AppIdentity.defaultUserId,
        stepRaw: String = "WELCOME",
        startedAt: Date = Date(),
        welcomeSeenAt: Date? = nil,
        captureIntroSeenAt: Date? = nil,
        profileCompletedAt: Date? = nil,
        captureSkippedAt: Date? = nil,
        captureCompletedAt: Date? = nil,
        firstOutfitOfferedAt: Date? = nil,
        lastActivityAt: Date = Date(),
        demoMode: Bool = false
    ) {
        self.userId = userId
        self.stepRaw = stepRaw
        self.startedAt = startedAt
        self.welcomeSeenAt = welcomeSeenAt
        self.captureIntroSeenAt = captureIntroSeenAt
        self.profileCompletedAt = profileCompletedAt
        self.captureSkippedAt = captureSkippedAt
        self.captureCompletedAt = captureCompletedAt
        self.firstOutfitOfferedAt = firstOutfitOfferedAt
        self.lastActivityAt = lastActivityAt
        self.demoMode = demoMode
    }
}

@Model
final class StyleProfileDraftEntity {
    @Attribute(.unique) var userId: UUID
    var revision: Int
    var answersJSON: Data?
    var summaryDraft: String?
    /// TEMPLATE | MODEL | USER
    var summaryDraftSourceRaw: String?
    var summaryForRevision: Int?
    var basedOnProfileVersion: Int?

    init(
        userId: UUID = AppIdentity.defaultUserId,
        revision: Int = 0,
        answersJSON: Data? = nil,
        summaryDraft: String? = nil,
        summaryDraftSourceRaw: String? = nil,
        summaryForRevision: Int? = nil,
        basedOnProfileVersion: Int? = nil
    ) {
        self.userId = userId
        self.revision = revision
        self.answersJSON = answersJSON
        self.summaryDraft = summaryDraft
        self.summaryDraftSourceRaw = summaryDraftSourceRaw
        self.summaryForRevision = summaryForRevision
        self.basedOnProfileVersion = basedOnProfileVersion
    }
}

@Model
final class PrivacyConsentEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var policyVersion: String
    var wardrobeImagesAcceptedAt: Date?
    var decidedAt: Date
    var withdrawnAt: Date?
    var selfieOptInAt: Date?

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        policyVersion: String,
        wardrobeImagesAcceptedAt: Date? = nil,
        decidedAt: Date = Date(),
        withdrawnAt: Date? = nil,
        selfieOptInAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.policyVersion = policyVersion
        self.wardrobeImagesAcceptedAt = wardrobeImagesAcceptedAt
        self.decidedAt = decidedAt
        self.withdrawnAt = withdrawnAt
        self.selfieOptInAt = selfieOptInAt
    }
}

@Model
final class CaptureBatchEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    /// CAMERA | LIBRARY | MANUAL
    var sourceRaw: String
    var createdAt: Date
    var readingAllowed: Bool
    var readingDecidedAt: Date
    var policyVersionAtChoice: String
    var captureIdsData: Data
    var reviewCursor: Int
    var closedAt: Date?

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        sourceRaw: String = "CAMERA",
        createdAt: Date = Date(),
        readingAllowed: Bool = false,
        readingDecidedAt: Date = Date(),
        policyVersionAtChoice: String = "",
        captureIds: [UUID] = [],
        reviewCursor: Int = 0,
        closedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.sourceRaw = sourceRaw
        self.createdAt = createdAt
        self.readingAllowed = readingAllowed
        self.readingDecidedAt = readingDecidedAt
        self.policyVersionAtChoice = policyVersionAtChoice
        self.captureIdsData = UUIDListCodec.encode(captureIds)
        self.reviewCursor = reviewCursor
        self.closedAt = closedAt
    }

    var captureIds: [UUID] {
        get { UUIDListCodec.decode(captureIdsData) }
        set { captureIdsData = UUIDListCodec.encode(newValue) }
    }
}

/// Pending capture — not a Garment (D-66 / R05). Structure only.
@Model
final class PendingCaptureEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var batchId: UUID
    var createdAt: Date
    var imageRevision: Int
    var masterURI: String
    var processedURI: String?
    var thumbnailURI: String?
    /// SAVED | PROCESSING | MASKED | CROPPED | PROCESS_FAILED
    var imageStateRaw: String
    var maskCoverage: Float?
    /// Slot chip / user choice; null = Auto
    var slotIntentRaw: String?
    /// NOT_REQUESTED | QUEUED | IN_FLIGHT | DONE | CAP_REACHED | RATE_LIMITED | FAILED | CANCELLED | SUSPENDED_POLICY
    var analysisStateRaw: String
    var analysisAttempts: Int
    var nextAttemptAt: Date?
    var activeRequestId: UUID?
    var analysisForRevision: Int?
    var proposalJSON: Data?
    var proposalConfidenceJSON: Data?
    var suggestedDisplayName: String?
    var warningsJSON: Data?
    var reviewDraftJSON: Data?
    /// PENDING | COMMITTED | DISCARDED
    var reviewStateRaw: String
    var garmentId: UUID?

    init(
        id: UUID = UUID(),
        userId: UUID = AppIdentity.defaultUserId,
        batchId: UUID,
        createdAt: Date = Date(),
        imageRevision: Int = 1,
        masterURI: String,
        processedURI: String? = nil,
        thumbnailURI: String? = nil,
        imageStateRaw: String = "SAVED",
        maskCoverage: Float? = nil,
        slotIntentRaw: String? = nil,
        analysisStateRaw: String = "NOT_REQUESTED",
        analysisAttempts: Int = 0,
        nextAttemptAt: Date? = nil,
        activeRequestId: UUID? = nil,
        analysisForRevision: Int? = nil,
        proposalJSON: Data? = nil,
        proposalConfidenceJSON: Data? = nil,
        suggestedDisplayName: String? = nil,
        warnings: [String] = [],
        reviewDraftJSON: Data? = nil,
        reviewStateRaw: String = "PENDING",
        garmentId: UUID? = nil
    ) {
        self.id = id
        self.userId = userId
        self.batchId = batchId
        self.createdAt = createdAt
        self.imageRevision = imageRevision
        self.masterURI = masterURI
        self.processedURI = processedURI
        self.thumbnailURI = thumbnailURI
        self.imageStateRaw = imageStateRaw
        self.maskCoverage = maskCoverage
        self.slotIntentRaw = slotIntentRaw
        self.analysisStateRaw = analysisStateRaw
        self.analysisAttempts = analysisAttempts
        self.nextAttemptAt = nextAttemptAt
        self.activeRequestId = activeRequestId
        self.analysisForRevision = analysisForRevision
        self.proposalJSON = proposalJSON
        self.proposalConfidenceJSON = proposalConfidenceJSON
        self.suggestedDisplayName = suggestedDisplayName
        self.warningsJSON = try? JSONEncoder().encode(warnings)
        self.reviewDraftJSON = reviewDraftJSON
        self.reviewStateRaw = reviewStateRaw
        self.garmentId = garmentId
    }
}
