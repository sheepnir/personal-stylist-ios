import Foundation

/// Shared DTO-level rewrite rules for D-69 so SwiftData and in-memory stores stay aligned.
enum DestructiveCascade {
    static func outfitsRemovingGarment(_ id: UUID, from outfits: [StubOutfit]) -> [StubOutfit] {
        outfits.filter { outfit in
            !outfit.assignments.contains { $0.garmentId == id }
        }
    }

    static func wearsRemovingGarment(
        _ id: UUID,
        from wears: [StubWearEvent],
        now: Date = Date()
    ) -> [StubWearEvent] {
        wears.map { wear in
            guard wear.garmentIds.contains(id) else { return wear }
            var next = wear
            next.garmentIds = wear.garmentIds.filter { $0 != id }
            if next.garmentIds.isEmpty {
                next.voidedAt = now
            }
            return next
        }
    }

    struct SetRewrite: Sendable {
        var kept: [StubSet]
        var deletedIds: Set<UUID>
    }

    static func setsRemovingGarment(_ id: UUID, from sets: [StubSet]) -> SetRewrite {
        var kept: [StubSet] = []
        var deleted: Set<UUID> = []
        for var set in sets {
            guard set.memberGarmentIds.contains(id) else {
                kept.append(set)
                continue
            }
            set.memberGarmentIds = set.memberGarmentIds.filter { $0 != id }
            if set.memberGarmentIds.isEmpty || (set.keepTogether && set.memberGarmentIds.count < 2) {
                deleted.insert(set.id)
            } else {
                kept.append(set)
            }
        }
        return SetRewrite(kept: kept, deletedIds: deleted)
    }

    static func garmentsClearingDeletedSets(
        _ garments: [StubGarment],
        deletedSetIds: Set<UUID>
    ) -> [StubGarment] {
        guard !deletedSetIds.isEmpty else { return garments }
        return garments.map { garment in
            guard let setId = garment.setId, deletedSetIds.contains(setId) else { return garment }
            var next = garment
            next.setId = nil
            return next
        }
    }

    static func isBlankUnconfirmedDraft(_ profile: StubStyleProfile) -> Bool {
        profile.confirmedAt == nil
            && profile.seedSource == nil
            && profile.age == nil
            && (profile.profession == nil || profile.profession?.isEmpty == true)
            && (profile.workEnvironment == nil || profile.workEnvironment?.isEmpty == true)
            && (profile.workEnvironmentLabel == nil || profile.workEnvironmentLabel?.isEmpty == true)
            && (profile.typicalWeekNotes == nil || profile.typicalWeekNotes?.isEmpty == true)
            && profile.goals.isEmpty
            && (profile.constraintsNotes == nil || profile.constraintsNotes?.isEmpty == true)
            && profile.experimentationLevel == nil
            && (profile.summary == nil || profile.summary?.isEmpty == true)
            && profile.summaryUserOwned == false
    }

    static func blankUnconfirmedDraft(id: UUID = UUID(), version: Int) -> StubStyleProfile {
        StubStyleProfile(
            id: id,
            age: nil,
            profession: nil,
            workEnvironment: nil,
            workEnvironmentLabel: nil,
            typicalWeekNotes: nil,
            goals: [],
            constraintsNotes: nil,
            experimentationLevel: nil,
            summary: nil,
            summaryUserOwned: false,
            version: version,
            confirmedAt: nil,
            seedSource: nil
        )
    }
}
