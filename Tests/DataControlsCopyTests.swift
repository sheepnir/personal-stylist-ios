import XCTest
@testable import PersonalStylist

/// D-69 / D-70 / D-71 — confirmation copy + LoopDemoModel session updates.
/// Disposable in-memory fixtures only. Cancel is UI-only (no store write).
final class DataControlsCopyTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "DataControlsCopyTests.\(UUID().uuidString)"
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

    // MARK: - Copy

    func testConfirmationCopyNamesScopeAndOmitsForbiddenPhrases() {
        let delete = DataControlsCopy.deleteGarmentMessage(name: "Canvas Tee")
        let reset = DataControlsCopy.resetProfileMessage
        let clear = DataControlsCopy.clearWardrobeMessage
        let joined = [delete, reset, clear].joined(separator: "\n")

        XCTAssertTrue(delete.contains("photos"))
        XCTAssertTrue(delete.contains("Looks"))
        XCTAssertTrue(delete.contains("style profile"))
        XCTAssertTrue(reset.contains("profile"))
        XCTAssertTrue(reset.contains("looks"))
        XCTAssertTrue(clear.contains("photos"))
        XCTAssertTrue(clear.contains("looks"))
        XCTAssertTrue(clear.contains("style profile"))

        XCTAssertEqual(DataControlsCopy.deleteGarmentAction, "Delete garment")
        XCTAssertEqual(DataControlsCopy.resetProfileAction, "Reset profile")
        XCTAssertEqual(DataControlsCopy.clearWardrobeAction, "Clear wardrobe and looks")
        XCTAssertEqual(DataControlsCopy.deleteGarmentSuccess, "Garment deleted")
        XCTAssertEqual(DataControlsCopy.clearWardrobeSuccess, "Wardrobe and looks cleared")
        XCTAssertEqual(DataControlsCopy.resetProfileSuccess, "Profile reset")

        for forbidden in ["Delete everything", "HTTP", "http://", "https://", "NSURL", "token"] {
            XCTAssertFalse(
                joined.contains(forbidden),
                "confirmation copy must not contain \(forbidden)"
            )
        }
        XCTAssertFalse(delete.contains("AVAILABLE"))
        XCTAssertFalse(reset.contains("confirmedAt"))
        XCTAssertFalse(clear.contains("GarmentEntity"))
    }

    func testCancelLeavesStoreUnchanged() async throws {
        let a = disposableGarment(name: "Canvas Tee", slot: .top)
        let store = InMemoryPersistenceStore(garments: [a], defaults: defaults)
        try await store.saveStyleProfile(disposableProfile(profession: "Tester"))
        let beforeGarments = await store.fetchGarments()
        let beforeProfile = await store.fetchStyleProfile()
        let beforeGeneration = store.dataGeneration

        // Cancel is UI-only: confirmation never calls the model.
        XCTAssertEqual(DataControlsCopy.cancel, "Cancel")
        XCTAssertEqual(beforeGarments.map(\.id), [a.id])
        XCTAssertEqual(beforeProfile?.profession, "Tester")
        XCTAssertEqual(store.dataGeneration, beforeGeneration)
        let after = await store.fetchGarments()
        XCTAssertEqual(after.map(\.id), beforeGarments.map(\.id))
    }

    // MARK: - Model / D-69

    @MainActor
    func testDeleteGarmentUpdatesSessionAndPreservesOthers() async throws {
        let keep = disposableGarment(name: "Keep Coat", slot: .outerwear)
        let doomed = disposableGarment(name: "Doomed Tee", slot: .top)
        let store = InMemoryPersistenceStore(garments: [keep, doomed], defaults: defaults)
        try await store.saveStyleProfile(disposableProfile(profession: "Tester"))
        try await store.saveOutfit(look(anchor: doomed, partner: keep))
        try await store.saveWearEvent(StubWearEvent(id: UUID(), garmentIds: [doomed.id], wornOn: Date()))

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.select(doomed)
        model.outfit = look(anchor: doomed, partner: keep)
        model.outfitWearable = true
        model.swapSlot = .top
        model.swapAlternatives = [
            StubSwapAlternative(id: keep.id, garment: keep, reason: "local", score: nil, setPartnerIds: [])
        ]

        let generationBefore = store.dataGeneration
        await model.deleteGarment(id: doomed.id)

        XCTAssertEqual(store.dataGeneration, generationBefore + 1)
        XCTAssertEqual(model.garments.map(\.id), [keep.id])
        XCTAssertEqual(model.selectedGarment?.id, keep.id)
        XCTAssertNil(model.outfit)
        XCTAssertFalse(model.outfitWearable)
        XCTAssertNil(model.swapSlot)
        XCTAssertTrue(model.swapAlternatives.isEmpty)
        XCTAssertEqual(model.styleProfile?.profession, "Tester")
        XCTAssertEqual(model.activeToast, DataControlsCopy.deleteGarmentSuccess)
        let leftoverLooks = await store.fetchOutfits()
        XCTAssertTrue(leftoverLooks.isEmpty)
    }

    // MARK: - Model / D-70

    @MainActor
    func testClearWardrobeAndLooksPreservesProfile() async throws {
        let top = disposableGarment(name: "Canvas Tee", slot: .top)
        let bottom = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(
            garments: [top, bottom],
            sets: [
                StubSet(
                    id: UUID(),
                    displayName: "Pair",
                    keepTogether: false,
                    memberGarmentIds: [top.id, bottom.id]
                ),
            ],
            defaults: defaults
        )
        try await store.saveStyleProfile(disposableProfile(profession: "Tester"))
        try await store.saveOutfit(look(anchor: top, partner: bottom))

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = look(anchor: top, partner: bottom)
        model.outfitWearable = true
        model.select(top)

        let generationBefore = store.dataGeneration
        await model.clearWardrobeAndLooks()

        XCTAssertEqual(store.dataGeneration, generationBefore + 1)
        XCTAssertTrue(model.garments.isEmpty)
        XCTAssertTrue(model.sets.isEmpty)
        XCTAssertNil(model.selectedGarment)
        XCTAssertNil(model.outfit)
        XCTAssertFalse(model.outfitWearable)
        XCTAssertEqual(model.styleProfile?.profession, "Tester")
        XCTAssertEqual(model.activeToast, DataControlsCopy.clearWardrobeSuccess)
        XCTAssertTrue(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        let leftoverLooks = await store.fetchOutfits()
        XCTAssertTrue(leftoverLooks.isEmpty)
    }

    // MARK: - Model / D-71

    @MainActor
    func testResetProfileReturnsBlankDraftAndKeepsWardrobe() async throws {
        let top = disposableGarment(name: "Canvas Tee", slot: .top)
        let store = InMemoryPersistenceStore(garments: [top], defaults: defaults)
        let confirmed = disposableProfile(profession: "Tester")
        try await store.saveStyleProfile(confirmed)
        try await store.saveOutfit(look(anchor: top, partner: nil))

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let board = look(anchor: top, partner: nil)
        model.outfit = board
        model.outfitWearable = true
        model.select(top)

        let generationBefore = store.dataGeneration
        await model.resetActiveStyleProfile()

        XCTAssertEqual(store.dataGeneration, generationBefore + 1)
        let profile = try XCTUnwrap(model.styleProfile)
        XCTAssertNotEqual(profile.id, confirmed.id)
        XCTAssertTrue(DestructiveCascade.isBlankUnconfirmedDraft(profile))
        XCTAssertNil(profile.seedSource)
        XCTAssertNil(profile.confirmedAt)
        XCTAssertEqual(model.garments.map(\.id), [top.id])
        XCTAssertEqual(model.outfit?.id, board.id)
        XCTAssertTrue(model.outfitWearable)
        XCTAssertEqual(model.activeToast, DataControlsCopy.resetProfileSuccess)
        XCTAssertTrue(SeedSuppression.isAutomaticProfileSeedSuppressed(in: defaults))
        XCTAssertFalse(
            model.validateBuildPreconditions(),
            "reset must gate generate until the new draft is confirmed"
        )
    }

    @MainActor
    func testLateEngineOutfitFromPreClearGenerationIsDropped() async throws {
        let top = disposableGarment(name: "Canvas Tee", slot: .top)
        let bottom = disposableGarment(name: "Navy Trouser", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [top, bottom], defaults: defaults)
        try await store.saveStyleProfile(disposableProfile(profession: "Tester"))
        let staleLook = look(anchor: top, partner: bottom)
        try await store.saveOutfit(staleLook)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = staleLook
        model.outfitWearable = true
        model.select(top)

        let capturedData = store.dataGeneration
        let capturedEngine = model.engineWorkGenerationForTests
        XCTAssertTrue(model.isCurrentStoreGeneration(capturedData))

        await model.clearWardrobeAndLooks()
        let clearedLooks = await store.fetchOutfits()
        XCTAssertTrue(clearedLooks.isEmpty)
        XCTAssertNil(model.outfit)

        let accepted = await model.applyLateEngineOutfitIfCurrent(
            staleLook,
            capturedEngineGeneration: capturedEngine,
            capturedDataGeneration: capturedData
        )
        XCTAssertFalse(accepted)
        XCTAssertFalse(model.isCurrentStoreGeneration(capturedData))
        let looks = await store.fetchOutfits()
        XCTAssertTrue(looks.isEmpty, "stale saveOutfit must not resurrect a cleared look")
        XCTAssertNil(model.outfit)
        XCTAssertFalse(model.outfitWearable)

        let persisted = await model.persistOutfitIfGenerationCurrent(
            staleLook,
            capturedDataGeneration: capturedData
        )
        XCTAssertFalse(persisted)
        let afterPersist = await store.fetchOutfits()
        XCTAssertTrue(afterPersist.isEmpty)
    }

    @MainActor
    func testLateEngineOutfitFromPreResetGenerationIsDropped() async throws {
        let top = disposableGarment(name: "Canvas Tee", slot: .top)
        let store = InMemoryPersistenceStore(garments: [top], defaults: defaults)
        try await store.saveStyleProfile(disposableProfile(profession: "Tester"))
        let staleLook = look(anchor: top, partner: nil)
        try await store.saveOutfit(staleLook)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.select(top)
        let capturedData = store.dataGeneration
        let capturedEngine = model.engineWorkGenerationForTests

        await model.resetActiveStyleProfile()
        XCTAssertFalse(model.validateBuildPreconditions())

        let accepted = await model.applyLateEngineOutfitIfCurrent(
            StubOutfit(
                id: UUID(),
                assignments: staleLook.assignments,
                rationaleSummary: "stale after reset",
                offlineCached: false
            ),
            capturedEngineGeneration: capturedEngine,
            capturedDataGeneration: capturedData
        )
        XCTAssertFalse(accepted)
        let looks = await store.fetchOutfits()
        XCTAssertEqual(looks.map(\.rationaleSummary), ["disposable look"])
    }

    @MainActor
    func testEnsureEditableStyleProfileCreatesBlankWhenMissing() async throws {
        SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
        let store = InMemoryPersistenceStore(garments: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertNil(model.styleProfile)

        await model.ensureEditableStyleProfile()
        let profile = try XCTUnwrap(model.styleProfile)
        XCTAssertTrue(DestructiveCascade.isBlankUnconfirmedDraft(profile))
        XCTAssertNotEqual(profile.seedSource, "founder")
    }

    // MARK: - Helpers

    private func disposableGarment(name: String, slot: StubSlot) -> StubGarment {
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
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
    }

    private func disposableProfile(profession: String) -> StubStyleProfile {
        StubStyleProfile(
            id: UUID(),
            age: 40,
            profession: profession,
            workEnvironment: "office",
            workEnvironmentLabel: "Office",
            typicalWeekNotes: "office",
            goals: ["look put together"],
            constraintsNotes: nil,
            experimentationLevel: 3,
            summary: "A confirmed test draft.",
            summaryUserOwned: true,
            version: 1,
            confirmedAt: Date(),
            seedSource: "test"
        )
    }

    private func look(anchor: StubGarment, partner: StubGarment?) -> StubOutfit {
        var assignments = [
            StubOutfitAssignment(slot: anchor.slot, garmentId: anchor.id, gapReason: nil, isAnchor: true),
        ]
        if let partner {
            assignments.append(
                StubOutfitAssignment(slot: partner.slot, garmentId: partner.id, gapReason: nil, isAnchor: false)
            )
        }
        return StubOutfit(
            id: UUID(),
            assignments: assignments,
            rationaleSummary: "disposable look",
            offlineCached: false
        )
    }
}
