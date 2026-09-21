import Foundation
import SwiftData

/// Local-first SwiftData store (D-13 / M0-11). Seeds from fixture JSON when empty.
final class SwiftDataPersistenceStore: PersistenceStore, @unchecked Sendable {
    var backendName: String { "SwiftData local + fixture seed" }

    private let workQueue = DispatchQueue(label: "PersonalStylist.persistence", qos: .userInitiated)
    private let container: ModelContainer
    let userId: UUID
    private let defaults: UserDefaults
    private let generationLock = NSLock()
    private var generation = 0

    var dataGeneration: Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    init(
        container: ModelContainer,
        userId: UUID = AppIdentity.defaultUserId,
        defaults: UserDefaults = .standard
    ) {
        self.container = container
        self.userId = userId
        self.defaults = defaults
    }

    /// Called from `App.init` before scenes appear (main thread).
    @MainActor
    func seedIfNeededSync(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? self.defaults
        ensureUser()
        seedGarmentsAndSetsIfEmpty(defaults: defaults)
        // GH #121: ordered before / owned by →V2 migration (see PersonalStylistMigrationPlan).
        // After V2 migration completed, never re-run backfill against the V2 store.
        if defaults.bool(forKey: PersonalStylistMigrationPlan.schemaV2MigrationCompletedKey) {
            if defaults.bool(forKey: Self.fixturePatternSurfaceBackfillKey) == false {
                defaults.set(true, forKey: Self.fixturePatternSurfaceBackfillKey)
            }
            return
        }
        backfillFixturePatternSurfaceOnce(defaults: defaults)
    }

    @MainActor
    private func ensureUser() {
        let uid = userId
        let context = container.mainContext
        let fd = FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == uid })
        if (try? context.fetch(fd))?.first != nil { return }
        context.insert(UserEntity(id: uid))
        try? context.save()
    }

    @MainActor
    private func seedGarmentsAndSetsIfEmpty(defaults: UserDefaults) {
        let context = container.mainContext
        let gfd = FetchDescriptor<GarmentEntity>()
        let count = (try? context.fetchCount(gfd)) ?? 0
        guard count == 0 else { return }
        if SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults) { return }

        let fixtures = FixtureWardrobeLoader.loadGarments()
        for stub in fixtures {
            let entity = StubEntityMapper.makeEntity(from: stub, userId: userId)
            context.insert(entity)
            GarmentIndexSync.upsert(entity: entity, in: context)
            if let path = stub.imagePath, !path.isEmpty {
                let img = GarmentImageEntity(
                    userId: userId,
                    originalURI: path,
                    isPrimary: true,
                    garment: entity
                )
                context.insert(img)
            }
        }

        let sets = FixtureWardrobeLoader.loadSets()
        for s in sets {
            context.insert(StubEntityMapper.makeSetEntity(from: s, userId: userId))
        }
        try? context.save()
    }

    /// UserDefaults key for the GH #121 pattern/surface seed repair (runs once per install).
    /// Owned by `PersonalStylistMigrationPlan` for →V2; kept here for call-site stability.
    static let fixturePatternSurfaceBackfillKey = PersonalStylistMigrationPlan.fixturePatternSurfaceBackfillKey

    /// Narrow, versioned repair: only fixture-ID rows that are still READY with nil
    /// pattern/surface (the old decode gap). Never rewrites color/formality/warmth, never
    /// runs again after the flag is set, so intentional clears survive relaunch.
    /// Must not run against a post-migration V2 store (#215) — gated in `seedIfNeededSync`
    /// and inside `FixturePatternSurfaceBackfill`.
    @MainActor
    func backfillFixturePatternSurfaceOnce(defaults: UserDefaults = .standard) {
        FixturePatternSurfaceBackfill.runIfNeeded(in: container.mainContext, defaults: defaults)
    }

    func fetchGarments() async -> [StubGarment] {
        let uid = userId
        return await perform { context in
            let prefix = uid.uuidString.lowercased() + "|"
            let indexFD = FetchDescriptor<GarmentQueryIndex>(
                predicate: #Predicate { $0.idxUserName.starts(with: prefix) },
                sortBy: [SortDescriptor(\.idxUserName)]
            )
            let garmentFD = FetchDescriptor<GarmentEntity>(
                predicate: #Predicate { $0.userId == uid }
            )
            let rows = (try? context.fetch(garmentFD)) ?? []
            var indexes = (try? context.fetch(indexFD)) ?? []
            if indexes.count != rows.count {
                let indexedIds = Set(indexes.map(\.garmentId))
                for row in rows where !indexedIds.contains(row.id) {
                    GarmentIndexSync.upsert(entity: row, in: context)
                }
                try? context.save()
                indexes = (try? context.fetch(indexFD)) ?? []
            }
            let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            let ordered: [GarmentEntity]
            if indexes.isEmpty {
                ordered = rows.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            } else {
                ordered = indexes.compactMap { byId[$0.garmentId] }
            }
            return ordered.map(StubEntityMapper.stub(from:))
        } ?? []
    }

    func saveGarment(_ garment: StubGarment) async throws {
        let uid = userId
        try await performThrowing { context in
            let id = garment.id
            let fd = FetchDescriptor<GarmentEntity>(predicate: #Predicate { $0.id == id })
            let entity: GarmentEntity
            if let existing = try context.fetch(fd).first {
                StubEntityMapper.apply(garment, to: existing)
                entity = existing
            } else {
                entity = StubEntityMapper.makeEntity(from: garment, userId: uid)
                context.insert(entity)
            }
            GarmentIndexSync.upsert(entity: entity, in: context)
            try context.save()
        }
    }

    func fetchOutfits() async -> [StubOutfit] {
        let uid = userId
        return await perform { context in
            let fd = FetchDescriptor<OutfitEntity>(
                predicate: #Predicate { $0.userId == uid },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let rows = (try? context.fetch(fd)) ?? []
            return rows.map(StubEntityMapper.stub(from:))
        } ?? []
    }

    func saveOutfit(_ outfit: StubOutfit) async throws {
        let uid = userId
        try await performThrowing { context in
            let id = outfit.id
            let fd = FetchDescriptor<OutfitEntity>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(fd).first {
                for assignment in existing.assignments {
                    context.delete(assignment)
                }
                existing.rationaleSummary = outfit.rationaleSummary
                existing.offlineCached = outfit.offlineCached
                existing.updatedAt = Date()
                existing.assignments = outfit.assignments.map { assignment in
                    OutfitAssignmentEntity(
                        id: assignment.id,
                        userId: uid,
                        slotRaw: assignment.slot.rawValue,
                        garmentId: assignment.garmentId,
                        isAnchor: assignment.isAnchor,
                        isLocked: assignment.isLocked,
                        gapReason: assignment.gapReason,
                        outfit: existing
                    )
                }
            } else {
                context.insert(StubEntityMapper.makeEntity(from: outfit, userId: uid))
            }
            try context.save()
        }
    }

    func fetchWearEvents() async -> [StubWearEvent] {
        let uid = userId
        return await perform { context in
            let fd = FetchDescriptor<WearEventEntity>(
                predicate: #Predicate { $0.userId == uid },
                sortBy: [SortDescriptor(\.wornOn, order: .reverse)]
            )
            let rows = (try? context.fetch(fd)) ?? []
            return rows.map(StubEntityMapper.stub(from:))
        } ?? []
    }

    func fetchWearEvents(on day: Date) async -> [StubWearEvent] {
        let uid = userId
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return await perform { context in
            let fd = FetchDescriptor<WearEventEntity>(
                predicate: #Predicate { event in
                    event.userId == uid && event.wornOn >= start && event.wornOn < end
                },
                sortBy: [SortDescriptor(\.wornOn, order: .reverse)]
            )
            let rows = (try? context.fetch(fd)) ?? []
            return rows.map(StubEntityMapper.stub(from:))
        } ?? []
    }

    func fetchWearAggregates() async -> WearAggregates {
        let uid = userId
        return await perform { context in
            Self.backfillMembershipsIfNeeded(userId: uid, context: context)
            let fd = FetchDescriptor<WearMembershipEntity>(
                predicate: #Predicate { $0.userId == uid && $0.voided == false }
            )
            let rows = (try? context.fetch(fd)) ?? []
            var counts: [UUID: Int] = [:]
            var lastWorn: [UUID: Date] = [:]
            for row in rows {
                counts[row.garmentId, default: 0] += 1
                if let existing = lastWorn[row.garmentId] {
                    if row.wornOn > existing { lastWorn[row.garmentId] = row.wornOn }
                } else {
                    lastWorn[row.garmentId] = row.wornOn
                }
            }
            return WearAggregates(counts: counts, lastWorn: lastWorn)
        } ?? WearAggregates(counts: [:], lastWorn: [:])
    }

    func saveWearEvent(_ event: StubWearEvent) async throws {
        let uid = userId
        try await performThrowing { context in
            let id = event.id
            let fd = FetchDescriptor<WearEventEntity>(predicate: #Predicate { $0.id == id })
            let entity: WearEventEntity
            if let existing = try context.fetch(fd).first {
                existing.garmentIds = event.garmentIds
                existing.wornOn = event.wornOn
                existing.voidedAt = event.voidedAt
                existing.sourceOutfitId = event.sourceOutfitId
                entity = existing
            } else {
                entity = StubEntityMapper.makeEntity(from: event, userId: uid)
                context.insert(entity)
            }
            WearMembershipSync.replace(event: entity, in: context)
            try context.save()
        }
    }

    func voidWearEvent(id: UUID) async throws {
        try await performThrowing { context in
            let fd = FetchDescriptor<WearEventEntity>(predicate: #Predicate { $0.id == id })
            guard let entity = try context.fetch(fd).first else { return }
            guard entity.voidedAt == nil else { return }
            entity.voidedAt = Date()
            WearMembershipSync.replace(event: entity, in: context)
            try context.save()
        }
    }

    func fetchStyleProfile() async -> StubStyleProfile? {
        let uid = userId
        return await perform { context -> StubStyleProfile? in
            let fd = FetchDescriptor<StyleProfileEntity>(
                predicate: #Predicate { $0.userId == uid },
                sortBy: [SortDescriptor(\.version, order: .reverse)]
            )
            guard let entity = try? context.fetch(fd).first else { return nil }
            return StubEntityMapper.stub(from: entity)
        } ?? nil
    }

    func saveStyleProfile(_ profile: StubStyleProfile) async throws {
        let uid = userId
        try await performThrowing { context in
            let id = profile.id
            let fd = FetchDescriptor<StyleProfileEntity>(predicate: #Predicate { $0.id == id })
            if let existing = try context.fetch(fd).first {
                StubEntityMapper.apply(profile, to: existing)
            } else {
                context.insert(StubEntityMapper.makeEntity(from: profile, userId: uid))
            }
            try context.save()
        }
    }

    func deleteGarment(id: UUID) async throws {
        let uid = userId
        let result = try await performThrowingValue { context -> (PhotoCleanup, Bool) in
            let cleanup = try Self.applyDeleteGarment(id: id, userId: uid, in: context)
            let remaining = try context.fetchCount(
                FetchDescriptor<GarmentEntity>(predicate: #Predicate { $0.userId == uid })
            )
            try context.save()
            return (cleanup, remaining == 0)
        }
        if result.1 {
            SeedSuppression.suppressAutomaticWardrobeSeed(in: defaults)
        }
        bumpGeneration()
        result.0.apply()
    }

    func clearWardrobeAndLooks() async throws {
        let uid = userId
        let cleanup = try await performThrowingValue { context -> PhotoCleanup in
            let cleanup = try Self.applyClearWardrobeAndLooks(userId: uid, in: context)
            try context.save()
            return cleanup
        }
        SeedSuppression.suppressAutomaticWardrobeSeed(in: defaults)
        bumpGeneration()
        cleanup.apply()
    }

    func resetActiveStyleProfile() async throws -> StubStyleProfile {
        let uid = userId
        let result = try await performThrowingValue { context -> (StubStyleProfile, PhotoCleanup) in
            let next = try Self.applyResetActiveStyleProfile(userId: uid, in: context)
            let cleanup = try Self.applyDiscardInFlightPendings(userId: uid, in: context)
            try context.save()
            return (next, cleanup)
        }
        SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
        bumpGeneration()
        result.1.apply()
        return result.0
    }

    func fetchSets() async -> [StubSet] {
        let uid = userId
        return await perform { context in
            let fd = FetchDescriptor<GarmentSetEntity>(predicate: #Predicate { $0.userId == uid })
            let rows = (try? context.fetch(fd)) ?? []
            return rows.map(StubEntityMapper.stub(from:))
        } ?? []
    }

    func fetchAllStyleProfiles() async -> [StubStyleProfile] {
        let uid = userId
        return await perform { context in
            let fd = FetchDescriptor<StyleProfileEntity>(
                predicate: #Predicate { $0.userId == uid },
                sortBy: [SortDescriptor(\.version, order: .reverse)]
            )
            let rows = (try? context.fetch(fd)) ?? []
            return rows.map(StubEntityMapper.stub(from:))
        } ?? []
    }

    /// Reads and writes use a background `ModelContext` so the main thread is not the store (#157).
    private func perform<T: Sendable>(_ work: @escaping (ModelContext) -> T) async -> T? {
        let container = container
        return await withCheckedContinuation { continuation in
            workQueue.async {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                continuation.resume(returning: work(context))
            }
        }
    }

    func performThrowing(_ work: @escaping (ModelContext) throws -> Void) async throws {
        try await performThrowingValue { context in
            try work(context)
        }
    }

    func performThrowingValue<T: Sendable>(_ work: @escaping (ModelContext) throws -> T) async throws -> T {
        let container = container
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            workQueue.async {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                do {
                    let value = try work(context)
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func bumpGeneration() {
        generationLock.lock()
        generation += 1
        generationLock.unlock()
    }

    private static func backfillMembershipsIfNeeded(userId: UUID, context: ModelContext) {
        let uid = userId
        let memberships = FetchDescriptor<WearMembershipEntity>(predicate: #Predicate { $0.userId == uid })
        let indexedEventIds = Set(((try? context.fetch(memberships)) ?? []).map(\.eventId))
        let eventsFD = FetchDescriptor<WearEventEntity>(predicate: #Predicate { $0.userId == uid })
        let events = (try? context.fetch(eventsFD)) ?? []
        guard !events.isEmpty else { return }
        // A newly saved event may already have rows before legacy events are backfilled.
        for event in events where !indexedEventIds.contains(event.id) {
            WearMembershipSync.replace(event: event, in: context)
        }
        try? context.save()
    }
}
