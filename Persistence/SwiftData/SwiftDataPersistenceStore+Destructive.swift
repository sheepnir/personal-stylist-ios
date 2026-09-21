import Foundation
import SwiftData

struct PhotoCleanup: Sendable {
    var garmentIds: [UUID]
    var imagePaths: [String]
    var referencedByOthers: Set<String>

    static let empty = PhotoCleanup(garmentIds: [], imagePaths: [], referencedByOthers: [])

    func apply() {
        for garmentId in garmentIds {
            UserGarmentPhotoStore.deleteOwnedFiles(
                for: garmentId,
                additionalPaths: imagePaths,
                excluding: referencedByOthers
            )
        }
        if garmentIds.isEmpty {
            for path in imagePaths where !referencedByOthers.contains(path) {
                UserGarmentPhotoStore.removeFile(imagePath: path)
            }
        }
    }
}

extension SwiftDataPersistenceStore {
    static func applyDeleteGarment(
        id: UUID,
        userId: UUID,
        in context: ModelContext
    ) throws -> PhotoCleanup {
        let uid = userId
        let deletedId = id
        let garmentFD = FetchDescriptor<GarmentEntity>(predicate: #Predicate { $0.id == deletedId })
        guard let garment = try context.fetch(garmentFD).first else {
            return .empty
        }

        var imagePaths = [garment.imagePath].compactMap { $0 }
        imagePaths.append(contentsOf: garment.images.flatMap { img in
            [img.originalURI, img.processedURI].compactMap { $0 }
        })

        let allGarments = try context.fetch(FetchDescriptor<GarmentEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        var referencedByOthers = Set<String>()
        for other in allGarments where other.id != id {
            if let path = other.imagePath { referencedByOthers.insert(path) }
            for img in other.images {
                referencedByOthers.insert(img.originalURI)
                if let processed = img.processedURI { referencedByOthers.insert(processed) }
            }
        }

        let outfitFD = FetchDescriptor<OutfitEntity>(predicate: #Predicate { $0.userId == uid })
        for outfit in try context.fetch(outfitFD) {
            if outfit.assignments.contains(where: { $0.garmentId == deletedId }) {
                context.delete(outfit)
            }
        }

        let now = Date()
        let wearFD = FetchDescriptor<WearEventEntity>(predicate: #Predicate { $0.userId == uid })
        for wear in try context.fetch(wearFD) where wear.garmentIds.contains(deletedId) {
            wear.garmentIds = wear.garmentIds.filter { $0 != deletedId }
            if wear.garmentIds.isEmpty {
                wear.voidedAt = now
            }
            WearMembershipSync.replace(event: wear, in: context)
        }
        let membershipFD = FetchDescriptor<WearMembershipEntity>(
            predicate: #Predicate { $0.userId == uid }
        )
        for row in try context.fetch(membershipFD) where row.garmentId == deletedId {
            context.delete(row)
        }

        let setFD = FetchDescriptor<GarmentSetEntity>(predicate: #Predicate { $0.userId == uid })
        var deletedSetIds = Set<UUID>()
        for set in try context.fetch(setFD) where set.memberGarmentIds.contains(deletedId) {
            set.memberGarmentIds = set.memberGarmentIds.filter { $0 != deletedId }
            if set.memberGarmentIds.isEmpty || (set.keepTogether && set.memberGarmentIds.count < 2) {
                deletedSetIds.insert(set.id)
                context.delete(set)
            }
        }
        if !deletedSetIds.isEmpty {
            for other in allGarments where other.id != id {
                if let setId = other.setId, deletedSetIds.contains(setId) {
                    other.setId = nil
                }
            }
        }

        let ruleFD = FetchDescriptor<PreferenceRuleEntity>(predicate: #Predicate { $0.userId == uid })
        for rule in try context.fetch(ruleFD) {
            switch PreferenceSubjectJSON.removing(deletedId, from: rule.subjectJSON) {
            case .styleLevel:
                break
            case .deleteRule:
                context.delete(rule)
            case .rewritten(let data):
                rule.subjectJSON = data
            }
        }

        let pendingFD = FetchDescriptor<PendingCaptureEntity>(
            predicate: #Predicate { $0.userId == uid }
        )
        for capture in try context.fetch(pendingFD) where capture.garmentId == deletedId {
            capture.garmentId = nil
            capture.reviewStateRaw = "DISCARDED"
        }

        let indexFD = FetchDescriptor<GarmentQueryIndex>(predicate: #Predicate { $0.garmentId == deletedId })
        for row in try context.fetch(indexFD) {
            context.delete(row)
        }

        context.delete(garment)

        return PhotoCleanup(
            garmentIds: [deletedId],
            imagePaths: imagePaths,
            referencedByOthers: referencedByOthers
        )
    }

    static func applyClearWardrobeAndLooks(
        userId: UUID,
        in context: ModelContext
    ) throws -> PhotoCleanup {
        let uid = userId
        let garments = try context.fetch(FetchDescriptor<GarmentEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        var imagePaths: [String] = []
        var garmentIds: [UUID] = []
        for garment in garments {
            garmentIds.append(garment.id)
            if let path = garment.imagePath { imagePaths.append(path) }
            for img in garment.images {
                imagePaths.append(img.originalURI)
                if let processed = img.processedURI { imagePaths.append(processed) }
            }
        }

        let pendingAll = try context.fetch(FetchDescriptor<PendingCaptureEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for capture in pendingAll {
            imagePaths.append(capture.masterURI)
            if let processed = capture.processedURI { imagePaths.append(processed) }
            if let thumb = capture.thumbnailURI { imagePaths.append(thumb) }
            context.delete(capture)
        }

        let batches = try context.fetch(FetchDescriptor<CaptureBatchEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for batch in batches {
            context.delete(batch)
        }

        for garment in garments {
            context.delete(garment)
        }

        let indexes = try context.fetch(FetchDescriptor<GarmentQueryIndex>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for row in indexes {
            context.delete(row)
        }

        let outfits = try context.fetch(FetchDescriptor<OutfitEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for outfit in outfits {
            context.delete(outfit)
        }

        let wears = try context.fetch(FetchDescriptor<WearEventEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for wear in wears {
            context.delete(wear)
        }
        let memberships = try context.fetch(FetchDescriptor<WearMembershipEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for row in memberships {
            context.delete(row)
        }

        let sets = try context.fetch(FetchDescriptor<GarmentSetEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for set in sets {
            context.delete(set)
        }

        let rules = try context.fetch(FetchDescriptor<PreferenceRuleEntity>(
            predicate: #Predicate { $0.userId == uid }
        ))
        for rule in rules where PreferenceSubjectJSON.namesAnyGarment(rule.subjectJSON) {
            context.delete(rule)
        }

        return PhotoCleanup(
            garmentIds: garmentIds,
            imagePaths: imagePaths,
            referencedByOthers: []
        )
    }

    static func applyResetActiveStyleProfile(
        userId: UUID,
        in context: ModelContext
    ) throws -> StubStyleProfile {
        let uid = userId
        let fd = FetchDescriptor<StyleProfileEntity>(
            predicate: #Predicate { $0.userId == uid },
            sortBy: [SortDescriptor(\.version, order: .reverse)]
        )
        let rows = try context.fetch(fd)
        if let current = rows.first, isBlankUnconfirmedDraft(current) {
            return StubEntityMapper.stub(from: current)
        }

        let nextVersion = (rows.first?.version ?? 0) + 1
        let entity = StyleProfileEntity(
            id: UUID(),
            userId: uid,
            version: nextVersion,
            age: nil,
            profession: nil,
            workEnvironment: nil,
            workEnvironmentLabel: nil,
            typicalWeekNotes: nil,
            goals: [],
            constraintsNotes: nil,
            experimentationLevel: nil,
            summaryText: nil,
            summaryUserOwned: false,
            summarySourceRaw: nil,
            answersJSON: nil,
            confirmedAt: nil,
            seedSource: nil
        )
        context.insert(entity)

        let draftFD = FetchDescriptor<StyleProfileDraftEntity>(predicate: #Predicate { $0.userId == uid })
        if let draft = try context.fetch(draftFD).first {
            draft.revision = 0
            draft.answersJSON = nil
            draft.summaryDraft = nil
            draft.summaryDraftSourceRaw = nil
            draft.summaryForRevision = nil
            draft.basedOnProfileVersion = nil
        }

        let onboardFD = FetchDescriptor<OnboardingStateEntity>(predicate: #Predicate { $0.userId == uid })
        if let onboarding = try context.fetch(onboardFD).first {
            onboarding.profileCompletedAt = nil
        }

        return StubEntityMapper.stub(from: entity)
    }

    private static func isBlankUnconfirmedDraft(_ entity: StyleProfileEntity) -> Bool {
        entity.confirmedAt == nil
            && entity.seedSource == nil
            && entity.age == nil
            && (entity.profession == nil || entity.profession?.isEmpty == true)
            && (entity.workEnvironment == nil || entity.workEnvironment?.isEmpty == true)
            && (entity.workEnvironmentLabel == nil || entity.workEnvironmentLabel?.isEmpty == true)
            && (entity.typicalWeekNotes == nil || entity.typicalWeekNotes?.isEmpty == true)
            && entity.goals.isEmpty
            && (entity.constraintsNotes == nil || entity.constraintsNotes?.isEmpty == true)
            && entity.experimentationLevel == nil
            && (entity.summaryText == nil || entity.summaryText?.isEmpty == true)
            && entity.summaryUserOwned == false
            && entity.summarySourceRaw == nil
            && entity.answersJSON == nil
    }
}
