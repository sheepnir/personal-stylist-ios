import XCTest
import SwiftData
import UIKit
@testable import PersonalStylist

/// D-69 / D-70 / D-71 — disposable in-memory / temp-disk stores only.
final class DestructivePersistenceTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "DestructivePersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Delete garment (D-69)

    @MainActor
    func testDeleteGarmentCascadePreservesOthersAndDoesNotResurrect() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let keepId = UUID()
        let deleteId = UUID()
        let setId = UUID()
        let jpeg = try Self.makeTinyJPEG()
        let photoPath = try UserGarmentPhotoStore.persistJPEG(from: jpeg, garmentId: deleteId)
        defer { UserGarmentPhotoStore.removeFiles(forGarmentId: deleteId) }

        let context = first.mainContext
        let keep = insertGarment(id: keepId, name: "Keep Coat", setId: setId, in: context)
        let doomed = insertGarment(id: deleteId, name: "Doomed Tee", setId: setId, imagePath: photoPath, in: context)
        context.insert(GarmentImageEntity(originalURI: photoPath, isPrimary: true, garment: doomed))

        context.insert(
            StubEntityMapper.makeSetEntity(
                from: StubSet(
                    id: setId,
                    displayName: "Keep together pair",
                    keepTogether: true,
                    memberGarmentIds: [keepId, deleteId]
                )
            )
        )

        let outfit = OutfitEntity(rationaleSummary: "look with doomed")
        outfit.assignments = [
            OutfitAssignmentEntity(slotRaw: StubSlot.top.rawValue, garmentId: deleteId, outfit: outfit),
            OutfitAssignmentEntity(slotRaw: StubSlot.bottom.rawValue, garmentId: keepId, outfit: outfit),
        ]
        context.insert(outfit)
        let survivorOutfit = OutfitEntity(rationaleSummary: "keep only")
        survivorOutfit.assignments = [
            OutfitAssignmentEntity(slotRaw: StubSlot.outerwear.rawValue, garmentId: keepId, outfit: survivorOutfit),
        ]
        context.insert(survivorOutfit)

        let pairWear = WearEventEntity(garmentIds: [keepId, deleteId], sourceRaw: "MANUAL_CONFIRM")
        context.insert(pairWear)
        WearMembershipSync.replace(event: pairWear, in: context)
        let soloWear = WearEventEntity(garmentIds: [deleteId], sourceRaw: "MANUAL_CONFIRM")
        context.insert(soloWear)
        WearMembershipSync.replace(event: soloWear, in: context)

        let confirmed = StyleProfileEntity(
            version: 1,
            profession: "Tester",
            confirmedAt: Date(),
            seedSource: "test"
        )
        context.insert(confirmed)
        try context.save()

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        XCTAssertEqual(store.dataGeneration, 0)
        try await store.deleteGarment(id: deleteId)
        XCTAssertEqual(store.dataGeneration, 1)

        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(photoPath))
        let after = await store.fetchGarments()
        XCTAssertEqual(after.map(\.id), [keepId])
        XCTAssertNil(after.first?.setId, "dissolved keepTogether set must clear setId")

        let outfits = await store.fetchOutfits()
        XCTAssertEqual(outfits.count, 1)
        XCTAssertEqual(outfits.first?.rationaleSummary, "keep only")

        let wears = await store.fetchWearEvents()
        let rewritten = try XCTUnwrap(wears.first { $0.id == pairWear.id })
        XCTAssertEqual(rewritten.garmentIds, [keepId])
        XCTAssertNil(rewritten.voidedAt)
        let voided = try XCTUnwrap(wears.first { $0.id == soloWear.id })
        XCTAssertTrue(voided.garmentIds.isEmpty)
        XCTAssertNotNil(voided.voidedAt)

        let inspect = ModelContext(first)
        XCTAssertEqual(try inspect.fetch(FetchDescriptor<GarmentQueryIndex>()).count, 1)
        XCTAssertEqual(try inspect.fetch(FetchDescriptor<GarmentSetEntity>()).count, 0)
        let memberships = try inspect.fetch(FetchDescriptor<WearMembershipEntity>())
        XCTAssertFalse(memberships.contains { $0.garmentId == deleteId })
        XCTAssertEqual(try inspect.fetch(FetchDescriptor<StyleProfileEntity>()).count, 1)
        _ = keep

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        relaunchStore.seedIfNeededSync(defaults: defaults)
        let relaunchedGarments = await relaunchStore.fetchGarments()
        XCTAssertEqual(Set(relaunchedGarments.map(\.id)), [keepId])
        XCTAssertFalse(relaunchedGarments.contains { $0.id == deleteId })
        XCTAssertFalse(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        alive = nil
    }

    @MainActor
    func testDeletingLastGarmentSuppressesWardrobeReseed() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let onlyId = UUID()
        let context = first.mainContext
        _ = insertGarment(id: onlyId, name: "Only", in: context)
        try context.save()

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        try await store.deleteGarment(id: onlyId)
        XCTAssertTrue(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        let afterDelete = await store.fetchGarments()
        XCTAssertTrue(afterDelete.isEmpty)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        relaunchStore.seedIfNeededSync(defaults: defaults)
        let afterRelaunch = await relaunchStore.fetchGarments()
        XCTAssertTrue(afterRelaunch.isEmpty)
        alive = nil
    }

    // MARK: - Clear (D-70)

    @MainActor
    func testClearEmptiesWardrobeLooksWearAndDoesNotReseed() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        store.seedIfNeededSync(defaults: defaults)
        let seeded = await store.fetchGarments()
        XCTAssertFalse(seeded.isEmpty, "first-install seed must still run when flags are unset")

        let profile = StubStyleProfile(
            id: UUID(),
            age: 40,
            profession: "Tester",
            workEnvironment: nil,
            workEnvironmentLabel: nil,
            typicalWeekNotes: nil,
            goals: ["look sharp"],
            constraintsNotes: nil,
            experimentationLevel: 2,
            summary: "Confirmed tester",
            summaryUserOwned: true,
            version: 2,
            confirmedAt: Date(),
            seedSource: "test"
        )
        try await store.saveStyleProfile(profile)
        try await store.saveOutfit(
            StubOutfit(
                id: UUID(),
                assignments: [
                    StubOutfitAssignment(slot: .top, garmentId: seeded[0].id, gapReason: nil, isAnchor: true),
                ],
                rationaleSummary: "seed look",
                offlineCached: false
            )
        )
        try await store.saveWearEvent(
            StubWearEvent(id: UUID(), garmentIds: [seeded[0].id], wornOn: Date())
        )

        let context = first.mainContext
        context.insert(
            PreferenceRuleEntity(
                kindRaw: "COLOR",
                polarityRaw: "AVOID_HARD",
                subjectJSON: try JSONSerialization.data(withJSONObject: ["color_family": "olive"])
            )
        )
        context.insert(
            PreferenceRuleEntity(
                kindRaw: "GARMENT",
                polarityRaw: "AVOID_HARD",
                subjectJSON: try JSONSerialization.data(withJSONObject: ["garmentId": seeded[0].id.uuidString])
            )
        )
        context.insert(
            OnboardingStateEntity(
                welcomeSeenAt: Date(),
                profileCompletedAt: Date()
            )
        )
        try context.save()

        let genBefore = store.dataGeneration
        try await store.clearWardrobeAndLooks()
        XCTAssertEqual(store.dataGeneration, genBefore + 1)
        XCTAssertTrue(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        XCTAssertTrue(defaults.bool(forKey: "ps.suppressAutomaticWardrobeSeed"))

        let clearedGarments = await store.fetchGarments()
        let clearedOutfits = await store.fetchOutfits()
        let clearedWears = await store.fetchWearEvents()
        let clearedSets = await store.fetchSets()
        XCTAssertTrue(clearedGarments.isEmpty)
        XCTAssertTrue(clearedOutfits.isEmpty)
        XCTAssertTrue(clearedWears.isEmpty)
        XCTAssertTrue(clearedSets.isEmpty)
        let fetchedProfile = await store.fetchStyleProfile()
        let keptProfile = try XCTUnwrap(fetchedProfile)
        XCTAssertEqual(keptProfile.id, profile.id)
        XCTAssertEqual(keptProfile.profession, "Tester")

        let inspect = ModelContext(first)
        XCTAssertEqual(try inspect.fetch(FetchDescriptor<UserEntity>()).count, 1)
        XCTAssertEqual(try inspect.fetch(FetchDescriptor<GarmentQueryIndex>()).count, 0)
        XCTAssertEqual(try inspect.fetch(FetchDescriptor<WearMembershipEntity>()).count, 0)
        let rules = try inspect.fetch(FetchDescriptor<PreferenceRuleEntity>())
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(PreferenceSubjectJSON.garmentIDs(in: rules[0].subjectJSON).count, 0)
        let onboarding = try XCTUnwrap(try inspect.fetch(FetchDescriptor<OnboardingStateEntity>()).first)
        XCTAssertNotNil(onboarding.welcomeSeenAt, "clear must not rewind welcome")
        XCTAssertNotNil(onboarding.profileCompletedAt)

        try await store.clearWardrobeAndLooks()
        XCTAssertEqual(store.dataGeneration, genBefore + 2)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        relaunchStore.seedIfNeededSync(defaults: defaults)
        let relaunchedGarments = await relaunchStore.fetchGarments()
        XCTAssertTrue(
            relaunchedGarments.isEmpty,
            "must not reseed fixtures when suppress flag is set"
        )
        let relaunchedProfile = await relaunchStore.fetchStyleProfile()
        XCTAssertEqual(relaunchedProfile?.id, profile.id)

        let added = disposableGarment(name: "Post-clear Jacket", slot: .jacket)
        try await relaunchStore.saveGarment(added)
        let afterAdd = await relaunchStore.fetchGarments()
        XCTAssertEqual(afterAdd.map(\.id), [added.id])
        alive = nil
    }

    // MARK: - Reset profile (D-71)

    @MainActor
    func testResetInsertsBlankDraftKeepsHistoricalAndGarments() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        let garment = disposableGarment(name: "Stay Shirt", slot: .top)
        try await store.saveGarment(garment)

        let historical = StubStyleProfile(
            id: UUID(),
            age: 41,
            profession: "Tester",
            workEnvironment: "office",
            workEnvironmentLabel: "Office",
            typicalWeekNotes: "desk",
            goals: ["neat"],
            constraintsNotes: nil,
            experimentationLevel: 1,
            summary: "Historical",
            summaryUserOwned: true,
            version: 3,
            confirmedAt: Date(),
            seedSource: "test"
        )
        try await store.saveStyleProfile(historical)

        let ctx = container.mainContext
        ctx.insert(
            StyleProfileDraftEntity(
                revision: 4,
                answersJSON: Data("{}".utf8),
                summaryDraft: "old draft",
                basedOnProfileVersion: 3
            )
        )
        ctx.insert(
            OnboardingStateEntity(
                stepRaw: "DONE",
                welcomeSeenAt: Date(),
                captureIntroSeenAt: Date(),
                profileCompletedAt: Date()
            )
        )
        try ctx.save()

        let blank = try await store.resetActiveStyleProfile()
        XCTAssertTrue(SeedSuppression.isAutomaticProfileSeedSuppressed(in: defaults))
        XCTAssertTrue(defaults.bool(forKey: "ps.suppressAutomaticProfileSeed"))
        XCTAssertNotEqual(blank.id, historical.id)
        XCTAssertEqual(blank.version, 4)
        XCTAssertNil(blank.confirmedAt)
        XCTAssertNil(blank.seedSource)
        XCTAssertNil(blank.profession)
        XCTAssertTrue(blank.goals.isEmpty)
        XCTAssertTrue(DestructiveCascade.isBlankUnconfirmedDraft(blank))

        let all = await store.fetchAllStyleProfiles()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.id == historical.id }?.profession, "Tester")
        let garmentsAfterReset = await store.fetchGarments()
        XCTAssertEqual(garmentsAfterReset.map(\.id), [garment.id])

        let inspect = ModelContext(container)
        let draft = try XCTUnwrap(try inspect.fetch(FetchDescriptor<StyleProfileDraftEntity>()).first)
        XCTAssertNil(draft.answersJSON)
        XCTAssertNil(draft.summaryDraft)
        XCTAssertEqual(draft.revision, 0)
        let onboarding = try XCTUnwrap(try inspect.fetch(FetchDescriptor<OnboardingStateEntity>()).first)
        XCTAssertNil(onboarding.profileCompletedAt)
        XCTAssertNotNil(onboarding.welcomeSeenAt)
        XCTAssertEqual(onboarding.stepRaw, "DONE")

        let again = try await store.resetActiveStyleProfile()
        XCTAssertEqual(again.id, blank.id, "repeat reset keeps a single current blank draft")
        let profilesAfterRepeat = await store.fetchAllStyleProfiles()
        XCTAssertEqual(profilesAfterRepeat.count, 2)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertEqual(model.styleProfile?.id, blank.id)
        XCTAssertNil(model.styleProfile?.seedSource)
        XCTAssertNil(model.styleProfile?.profession)
    }

    @MainActor
    func testFounderSeedNotAppliedWhenProfileSuppressSet() async throws {
        SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
        let store = InMemoryPersistenceStore(garments: [], defaults: defaults)
        let beforeLoad = await store.fetchStyleProfile()
        XCTAssertNil(beforeLoad)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertNil(model.styleProfile)
        let afterLoad = await store.fetchStyleProfile()
        XCTAssertNil(afterLoad)
        XCTAssertFalse(
            SeedSuppression.shouldWriteAutomaticProfileSeed(hasExistingProfile: false, defaults: defaults)
        )
    }

    // MARK: - Upgrade / first install

    @MainActor
    func testUpgradeMigratedFixtureCountsUnchangedWithoutClear() async throws {
        let opened = try TestModelContainers.makeFromLegacyFixture(.seededWardrobe)
        var container: ModelContainer? = opened.container
        defer {
            container = nil
            try? FileManager.default.removeItem(at: opened.cleanupRoot)
        }
        let inspect = ModelContext(opened.container)
        let garments = try inspect.fetchCount(FetchDescriptor<GarmentEntity>())
        let profiles = try inspect.fetchCount(FetchDescriptor<StyleProfileEntity>())
        let wears = try inspect.fetchCount(FetchDescriptor<WearEventEntity>())
        let sets = try inspect.fetchCount(FetchDescriptor<GarmentSetEntity>())
        XCTAssertEqual(garments, FixtureWardrobeLoader.loadGarments().count)
        XCTAssertEqual(profiles, 0)
        XCTAssertEqual(wears, 1)
        XCTAssertEqual(sets, FixtureWardrobeLoader.loadSets().count)
        XCTAssertFalse(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        XCTAssertFalse(SeedSuppression.isAutomaticProfileSeedSuppressed(in: defaults))

        let store = SwiftDataPersistenceStore(container: opened.container, defaults: defaults)
        store.seedIfNeededSync(defaults: defaults)
        XCTAssertEqual(try inspect.fetchCount(FetchDescriptor<GarmentEntity>()), garments)
        XCTAssertEqual(try inspect.fetchCount(FetchDescriptor<StyleProfileEntity>()), profiles)
        _ = container
        container = nil
    }

    @MainActor
    func testFirstInstallStillSeedsWhenFlagsUnset() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        XCTAssertFalse(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        store.seedIfNeededSync(defaults: defaults)
        let seededGarments = await store.fetchGarments()
        let seededSets = await store.fetchSets()
        XCTAssertEqual(seededGarments.count, FixtureWardrobeLoader.loadGarments().count)
        XCTAssertEqual(seededSets.count, FixtureWardrobeLoader.loadSets().count)
    }

    // MARK: - Repeat / generation

    @MainActor
    func testRepeatDeleteClearResetAreNoOpSuccessAndGenerationIncrements() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        XCTAssertEqual(store.dataGeneration, 0)

        try await store.deleteGarment(id: UUID())
        XCTAssertEqual(store.dataGeneration, 1)
        try await store.clearWardrobeAndLooks()
        XCTAssertEqual(store.dataGeneration, 2)
        let first = try await store.resetActiveStyleProfile()
        XCTAssertEqual(store.dataGeneration, 3)
        let second = try await store.resetActiveStyleProfile()
        XCTAssertEqual(store.dataGeneration, 4)
        XCTAssertEqual(first.id, second.id)
        let profiles = await store.fetchAllStyleProfiles()
        let garments = await store.fetchGarments()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(garments.isEmpty)
    }

    // MARK: - In-memory store

    func testInMemoryDeleteClearResetMatchSwiftDataSemantics() async throws {
        let a = disposableGarment(name: "Mem A", slot: .top)
        let b = disposableGarment(name: "Mem B", slot: .bottom)
        var aLinked = a
        let setId = UUID()
        aLinked.setId = setId
        var bLinked = b
        bLinked.setId = setId
        let store = InMemoryPersistenceStore(
            garments: [aLinked, bLinked],
            sets: [
                StubSet(id: setId, displayName: "Pair", keepTogether: true, memberGarmentIds: [a.id, b.id]),
            ],
            defaults: defaults
        )
        try await store.saveOutfit(
            StubOutfit(
                id: UUID(),
                assignments: [
                    StubOutfitAssignment(slot: .top, garmentId: a.id, gapReason: nil, isAnchor: true),
                    StubOutfitAssignment(slot: .bottom, garmentId: b.id, gapReason: nil, isAnchor: false),
                ],
                rationaleSummary: "both",
                offlineCached: false
            )
        )
        try await store.saveOutfit(
            StubOutfit(
                id: UUID(),
                assignments: [
                    StubOutfitAssignment(slot: .bottom, garmentId: b.id, gapReason: nil, isAnchor: true),
                ],
                rationaleSummary: "b only",
                offlineCached: false
            )
        )
        let pairWear = StubWearEvent(id: UUID(), garmentIds: [a.id, b.id], wornOn: Date())
        let solo = StubWearEvent(id: UUID(), garmentIds: [a.id], wornOn: Date())
        try await store.saveWearEvent(pairWear)
        try await store.saveWearEvent(solo)
        try await store.saveStyleProfile(
            StubStyleProfile(
                id: UUID(),
                age: nil,
                profession: "Tester",
                workEnvironment: nil,
                workEnvironmentLabel: nil,
                typicalWeekNotes: nil,
                goals: [],
                constraintsNotes: nil,
                experimentationLevel: nil,
                summary: nil,
                summaryUserOwned: false,
                version: 1,
                confirmedAt: Date(),
                seedSource: "test"
            )
        )

        XCTAssertEqual(store.dataGeneration, 0)
        try await store.deleteGarment(id: a.id)
        XCTAssertEqual(store.dataGeneration, 1)
        let afterDelete = await store.fetchGarments()
        let afterSets = await store.fetchSets()
        let afterOutfits = await store.fetchOutfits()
        XCTAssertEqual(afterDelete.map(\.id), [b.id])
        XCTAssertNil(afterDelete.first?.setId)
        XCTAssertTrue(afterSets.isEmpty)
        XCTAssertEqual(afterOutfits.map(\.rationaleSummary), ["b only"])
        let wears = await store.fetchWearEvents()
        XCTAssertEqual(wears.first { $0.id == pairWear.id }?.garmentIds, [b.id])
        XCTAssertTrue(wears.first { $0.id == solo.id }?.garmentIds.isEmpty ?? false)
        XCTAssertNotNil(wears.first { $0.id == solo.id }?.voidedAt)
        let profileAfterDelete = await store.fetchStyleProfile()
        XCTAssertEqual(profileAfterDelete?.profession, "Tester")

        try await store.deleteGarment(id: a.id)
        XCTAssertEqual(store.dataGeneration, 2)

        try await store.clearWardrobeAndLooks()
        XCTAssertEqual(store.dataGeneration, 3)
        let clearedG = await store.fetchGarments()
        let clearedO = await store.fetchOutfits()
        let clearedW = await store.fetchWearEvents()
        let clearedP = await store.fetchStyleProfile()
        XCTAssertTrue(clearedG.isEmpty)
        XCTAssertTrue(clearedO.isEmpty)
        XCTAssertTrue(clearedW.isEmpty)
        XCTAssertEqual(clearedP?.profession, "Tester")
        XCTAssertTrue(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))

        let blank = try await store.resetActiveStyleProfile()
        XCTAssertEqual(store.dataGeneration, 4)
        XCTAssertTrue(DestructiveCascade.isBlankUnconfirmedDraft(blank))
        let profiles = await store.fetchAllStyleProfiles()
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.contains { $0.profession == "Tester" })
        try await store.resetActiveStyleProfile()
        let afterRepeatReset = await store.fetchAllStyleProfiles()
        XCTAssertEqual(afterRepeatReset.count, 2)
    }

    // MARK: - Photos

    func testRemoveFileDeletesOwnedPhotoAndIsSafeIfMissing() throws {
        let id = UUID()
        let jpeg = try Self.makeTinyJPEG()
        let path = try UserGarmentPhotoStore.persistJPEG(from: jpeg, garmentId: id)
        XCTAssertNotNil(UserGarmentPhotoStore.loadThumbnail(imagePath: path, maxPixel: 64))
        XCTAssertTrue(UserGarmentPhotoStore.isOwnedUserFile(path))
        XCTAssertFalse(UserGarmentPhotoStore.isOwnedUserFile("images/synthetic_fixture.svg"))

        UserGarmentPhotoStore.removeFile(imagePath: path)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(path))
        UserGarmentPhotoStore.removeFile(imagePath: path)
        UserGarmentPhotoStore.removeFiles(forGarmentId: id)
        UserGarmentPhotoStore.removeFile(imagePath: "images/synthetic_fixture.svg")
    }

    func testPreferenceSubjectJSONRewritesAndLeavesStyleRules() throws {
        let gone = UUID()
        let stay = UUID()
        let only = try JSONSerialization.data(withJSONObject: ["garmentId": gone.uuidString])
        XCTAssertEqual(PreferenceSubjectJSON.removing(gone, from: only), .deleteRule)

        let pair = try JSONSerialization.data(withJSONObject: ["pair": [gone.uuidString, stay.uuidString]])
        switch PreferenceSubjectJSON.removing(gone, from: pair) {
        case .rewritten(let data):
            XCTAssertEqual(PreferenceSubjectJSON.garmentIDs(in: data), [stay])
        default:
            XCTFail("expected rewritten pair")
        }

        let style = try JSONSerialization.data(withJSONObject: ["color_family": "olive"])
        XCTAssertEqual(PreferenceSubjectJSON.removing(gone, from: style), .styleLevel)
        XCTAssertFalse(PreferenceSubjectJSON.namesAnyGarment(style))
    }

    // MARK: - Helpers

    private func disposableGarment(name: String, slot: StubSlot, setId: UUID? = nil) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 3,
            warmth: 3,
            setId: setId,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
    }

    @discardableResult
    private func insertGarment(
        id: UUID,
        name: String,
        setId: UUID? = nil,
        imagePath: String? = nil,
        in context: ModelContext
    ) -> GarmentEntity {
        let entity = GarmentEntity(
            id: id,
            displayName: name,
            slotRaw: StubSlot.top.rawValue,
            setId: setId,
            readinessRaw: StubReadiness.ready.rawValue,
            formality: 3,
            warmth: 3,
            imagePath: imagePath
        )
        context.insert(entity)
        GarmentIndexSync.upsert(entity: entity, in: context)
        return entity
    }

    private static func makeTinyJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "DestructivePersistenceTests", code: 1)
        }
        return data
    }
}
