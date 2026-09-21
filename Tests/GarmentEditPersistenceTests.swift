import XCTest
import SwiftData
@testable import PersonalStylist

/// D-72 — garment edit provenance, price integrity, wear void.
/// Disposable in-memory / temp-disk stores only. Never a real on-device store.
final class GarmentEditPersistenceTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "GarmentEditPersistenceTests.\(UUID().uuidString)"
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

    // MARK: - 1. Edit READY + relaunch

    @MainActor
    func testEditReadyPreservesIdentitySetsAttributeSourceAndRelaunches() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let setId = UUID()
        var garment = disposableReadyGarment(name: "Edit Coat", slot: .outerwear, setId: setId)
        garment.imagePath = "images/synthetic_edit.svg"
        garment.createdAt = createdAt

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        try await store.saveGarment(garment)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        let saved = try await completeEdit(
            model,
            garment,
            name: "Renamed Coat",
            slot: .jacket,
            color: StubColorPrimary(family: "olive", hex: "#4A5D23", name: "Olive"),
            pattern: "HERRINGBONE",
            surface: "TEXTURED",
            formality: 4,
            warmth: 4
        )
        XCTAssertTrue(saved)

        let edited = try XCTUnwrap(model.garments.first { $0.id == garment.id })
        XCTAssertEqual(edited.id, garment.id)
        XCTAssertEqual(edited.createdAt, createdAt)
        XCTAssertEqual(edited.imagePath, "images/synthetic_edit.svg")
        XCTAssertEqual(edited.setId, setId)
        XCTAssertEqual(edited.displayName, "Renamed Coat")
        XCTAssertEqual(edited.displayNameSource, "USER")
        XCTAssertEqual(edited.slot, .jacket)
        XCTAssertEqual(edited.pattern, "HERRINGBONE")
        XCTAssertEqual(edited.attributeSource["slot"], "USER")
        XCTAssertEqual(edited.attributeSource["color"], "USER")
        XCTAssertEqual(edited.attributeSource["pattern"], "USER")
        XCTAssertEqual(edited.attributeSource["surface"], "USER")
        XCTAssertEqual(edited.attributeSource["formality"], "USER")
        XCTAssertEqual(edited.attributeSource["warmth"], "USER")

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        let rows = await relaunchStore.fetchGarments()
        let persisted = try XCTUnwrap(rows.first { $0.id == garment.id })
        XCTAssertEqual(persisted.displayName, "Renamed Coat")
        XCTAssertEqual(persisted.displayNameSource, "USER")
        XCTAssertEqual(persisted.slot, .jacket)
        XCTAssertEqual(persisted.imagePath, "images/synthetic_edit.svg")
        XCTAssertEqual(persisted.setId, setId)
        XCTAssertEqual(persisted.createdAt, createdAt)
        XCTAssertEqual(persisted.attributeSource["slot"], "USER")
        XCTAssertEqual(persisted.attributeSource["pattern"], "USER")
        alive = nil
    }

    @MainActor
    func testRequireCompleteRejectsIncompleteReadySave() async throws {
        let store = InMemoryPersistenceStore(garments: [disposableReadyGarment()], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let g = try XCTUnwrap(model.garments.first)

        let ok = await model.completeReadiness(
            id: g.id,
            slot: .top,
            displayName: "Should Not Save",
            displayNameIsUserSet: true,
            color: g.colorPrimary ?? StubColorPrimary(family: "navy", hex: nil, name: nil),
            pattern: "",
            surface: g.surface ?? "SMOOTH",
            formality: g.formality,
            warmth: g.warmth,
            requireComplete: true
        )
        XCTAssertFalse(ok)
        let unchanged = try XCTUnwrap(model.garments.first { $0.id == g.id })
        XCTAssertEqual(unchanged.displayName, g.displayName)
        XCTAssertEqual(unchanged.readiness, .ready)
        XCTAssertEqual(unchanged.pattern, "SOLID")
    }

    @MainActor
    func testReadyBecomesDraftWhenRequiredFieldCleared() async throws {
        let store = InMemoryPersistenceStore(garments: [disposableReadyGarment()], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let g = try XCTUnwrap(model.garments.first)

        let ok = await model.completeReadiness(
            id: g.id,
            color: g.colorPrimary ?? StubColorPrimary(family: "navy", hex: nil, name: nil),
            pattern: "",
            surface: g.surface ?? "SMOOTH",
            formality: g.formality,
            warmth: g.warmth,
            requireComplete: false
        )
        XCTAssertTrue(ok)
        let draft = try XCTUnwrap(model.garments.first { $0.id == g.id })
        XCTAssertEqual(draft.readiness, .draft)
        XCTAssertNil(draft.pattern)
        XCTAssertEqual(draft.attributeSource["pattern"], "USER")
        XCTAssertEqual(draft.id, g.id)
        XCTAssertEqual(draft.imagePath, g.imagePath)
        XCTAssertEqual(draft.setId, g.setId)
    }

    // MARK: - 2. Price integrity

    @MainActor
    func testPricePersistsNilVersusPositiveNeverStoresZero() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        var garment = disposableReadyGarment(name: "Priced Jacket")
        try await store.saveGarment(garment)

        garment.purchasePrice = nil
        garment.purchaseCurrency = "USD"
        try await store.saveGarment(garment)
        var rows = await store.fetchGarments()
        var loaded = try XCTUnwrap(rows.first { $0.id == garment.id })
        XCTAssertNil(loaded.purchasePrice)
        XCTAssertNil(loaded.purchaseCurrency)

        garment.purchasePrice = Decimal(string: "89.50")
        garment.purchaseCurrency = "USD"
        try await store.saveGarment(garment)
        rows = await store.fetchGarments()
        loaded = try XCTUnwrap(rows.first { $0.id == garment.id })
        XCTAssertEqual(loaded.purchasePrice, Decimal(string: "89.50"))
        XCTAssertEqual(loaded.purchaseCurrency, "USD")

        garment.purchasePrice = 0
        garment.purchaseCurrency = "USD"
        try await store.saveGarment(garment)
        rows = await store.fetchGarments()
        loaded = try XCTUnwrap(rows.first { $0.id == garment.id })
        XCTAssertNil(loaded.purchasePrice, "zero must not persist as a price")
        XCTAssertNil(loaded.purchaseCurrency)

        let memory = InMemoryPersistenceStore(garments: [disposableReadyGarment(name: "Memory Price")], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: memory, preferences: defaults)
        await model.load()
        let id = try XCTUnwrap(model.garments.first?.id)
        let rejectedZero = await model.savePurchaseInfo(id: id, price: 0, currency: "USD", purchaseDate: nil, priorWearBucket: nil)
        XCTAssertFalse(rejectedZero)
        XCTAssertNil(model.garments.first?.purchasePrice)
        let cleared = await model.savePurchaseInfo(id: id, price: nil, currency: "USD", purchaseDate: nil, priorWearBucket: nil)
        XCTAssertTrue(cleared)
        XCTAssertNil(model.garments.first?.purchasePrice)
        let savedPrice = await model.savePurchaseInfo(id: id, price: Decimal(40), currency: "USD", purchaseDate: nil, priorWearBucket: nil)
        XCTAssertTrue(savedPrice)
        XCTAssertEqual(model.garments.first?.purchasePrice, Decimal(40))
    }

    // MARK: - 3. Void wear

    @MainActor
    func testVoidWearDropsAggregatesKeepsSiblingsAndRepeatsAsNoop() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        var coat = disposableReadyGarment(name: "Void Coat", slot: .outerwear)
        let pants = disposableReadyGarment(name: "Void Pants", slot: .bottom)
        try await store.saveGarment(coat)
        try await store.saveGarment(pants)

        let older = Date(timeIntervalSince1970: 1_725_000_000)
        let newer = Date(timeIntervalSince1970: 1_725_200_000)
        let pair = StubWearEvent(id: UUID(), garmentIds: [coat.id, pants.id], wornOn: older)
        let solo = StubWearEvent(id: UUID(), garmentIds: [coat.id], wornOn: newer)
        try await store.saveWearEvent(pair)
        try await store.saveWearEvent(solo)

        let before = await store.fetchWearAggregates()
        XCTAssertEqual(before.counts[coat.id], 2)
        XCTAssertEqual(before.counts[pants.id], 1)

        try await store.voidWearEvent(id: pair.id)
        let afterVoidEvents = await store.fetchWearEvents()
        let voided = try XCTUnwrap(afterVoidEvents.first { $0.id == pair.id })
        XCTAssertNotNil(voided.voidedAt)
        XCTAssertEqual(voided.garmentIds, [coat.id, pants.id])
        XCTAssertEqual(voided.wornOn, older)
        XCTAssertNil(voided.sourceOutfitId)

        let after = await store.fetchWearAggregates()
        XCTAssertEqual(after.counts[coat.id], 1)
        XCTAssertNil(after.counts[pants.id])
        XCTAssertEqual(after.lastWorn[coat.id], newer)

        let firstVoidedAt = try XCTUnwrap(voided.voidedAt)
        try await store.voidWearEvent(id: pair.id)
        try await store.voidWearEvent(id: UUID())
        let repeatEvents = await store.fetchWearEvents()
        let again = try XCTUnwrap(repeatEvents.first { $0.id == pair.id })
        XCTAssertEqual(again.voidedAt, firstVoidedAt)
        XCTAssertEqual(again.garmentIds, [coat.id, pants.id])

        let inspect = ModelContext(container)
        let memberships = try inspect.fetch(FetchDescriptor<WearMembershipEntity>())
        let pairRows = memberships.filter { $0.eventId == pair.id }
        XCTAssertEqual(pairRows.count, 2)
        XCTAssertTrue(pairRows.allSatisfy(\.voided))
        XCTAssertEqual(Set(pairRows.map(\.garmentId)), [coat.id, pants.id])

        coat.purchasePrice = Decimal(100)
        coat.purchaseCurrency = "USD"
        try await store.saveGarment(coat)
        let pricedRows = await store.fetchGarments()
        let loadedCoat = try XCTUnwrap(pricedRows.first { $0.id == coat.id })
        let beforeCPW = CostPerWearCopy.summary(for: loadedCoat, confirmedWears: 2)
        let afterCPW = CostPerWearCopy.summary(for: loadedCoat, confirmedWears: after.counts[coat.id] ?? 0)
        XCTAssertNotEqual(beforeCPW.cpwLine, afterCPW.cpwLine)
    }

    @MainActor
    func testVoidWearModelHistoryHelpers() async throws {
        let coat = disposableReadyGarment(name: "History Coat")
        let pants = disposableReadyGarment(name: "History Pants", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [coat, pants], sets: [], defaults: defaults)
        let older = Date(timeIntervalSince1970: 1_724_000_000)
        let newer = Date(timeIntervalSince1970: 1_726_000_000)
        let pair = StubWearEvent(id: UUID(), garmentIds: [coat.id, pants.id], wornOn: older)
        let solo = StubWearEvent(id: UUID(), garmentIds: [coat.id], wornOn: newer)
        try await store.saveWearEvent(pair)
        try await store.saveWearEvent(solo)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertEqual(model.wearCount(for: coat.id), 2)
        XCTAssertEqual(model.wearHistory(for: coat.id).map(\.id), [solo.id, pair.id])
        XCTAssertEqual(model.recentWearHistory(for: coat.id).count, 2)

        await model.voidWear(id: pair.id)
        XCTAssertEqual(model.wearCount(for: coat.id), 1)
        XCTAssertEqual(model.wearHistory(for: coat.id).map(\.id), [solo.id])
        let all = model.wearHistoryAll(for: coat.id)
        XCTAssertEqual(all.map(\.id), [solo.id, pair.id])
        XCTAssertTrue(try XCTUnwrap(all.first { $0.id == pair.id }).isVoided)
        XCTAssertEqual(try XCTUnwrap(all.first { $0.id == pair.id }).garmentIds, [coat.id, pants.id])

        await model.voidWear(id: pair.id)
        XCTAssertEqual(model.wearCount(for: coat.id), 1)
    }

    // MARK: - 4. Slot change keeps looks and sets

    @MainActor
    func testSlotChangeDoesNotDeleteLooksOrDissolveSets() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        let setId = UUID()
        let memberA = disposableReadyGarment(name: "Set Jacket", slot: .jacket, setId: setId)
        let memberB = disposableReadyGarment(name: "Set Pants", slot: .bottom, setId: setId)
        try await store.saveGarment(memberA)
        try await store.saveGarment(memberB)
        let stubSet = StubSet(
            id: setId,
            displayName: "Keep together pair",
            keepTogether: true,
            memberGarmentIds: [memberA.id, memberB.id]
        )
        let context = container.mainContext
        context.insert(StubEntityMapper.makeSetEntity(from: stubSet))
        try context.save()

        let look = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .jacket, garmentId: memberA.id, gapReason: nil, isAnchor: true),
                StubOutfitAssignment(slot: .bottom, garmentId: memberB.id, gapReason: nil, isAnchor: false),
            ],
            rationaleSummary: "keep this look",
            offlineCached: true
        )
        try await store.saveOutfit(look)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let ok = try await completeEdit(
            model,
            memberA,
            name: memberA.displayName,
            slot: .midLayer,
            color: memberA.colorPrimary ?? StubColorPrimary(family: "navy", hex: nil, name: nil),
            pattern: memberA.pattern ?? "SOLID",
            surface: memberA.surface ?? "SMOOTH",
            formality: memberA.formality,
            warmth: memberA.warmth
        )
        XCTAssertTrue(ok)

        let outfits = await store.fetchOutfits()
        XCTAssertEqual(outfits.count, 1)
        XCTAssertEqual(outfits.first?.id, look.id)
        XCTAssertEqual(Set(outfits.first?.assignments.compactMap(\.garmentId) ?? []), [memberA.id, memberB.id])

        let sets = await store.fetchSets()
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.id, setId)
        XCTAssertEqual(Set(sets.first?.memberGarmentIds ?? []), [memberA.id, memberB.id])
        XCTAssertTrue(sets.first?.keepTogether == true)

        let afterSlot = await store.fetchGarments()
        let edited = try XCTUnwrap(afterSlot.first { $0.id == memberA.id })
        XCTAssertEqual(edited.slot, .midLayer)
        XCTAssertEqual(edited.setId, setId)
        XCTAssertEqual(edited.id, memberA.id)
    }

    // MARK: - 4b. Jeans slot correction + stale generate (#120)

    @MainActor
    func testJeansSlotCorrectionClearsSessionOutfitKeepsSavedLookAndRelaunchesOnce() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let createdAt = Date(timeIntervalSince1970: 1_700_100_000)
        var jeans = disposableReadyGarment(name: "Jeans", slot: .top)
        jeans.imagePath = "images/synthetic_jeans.svg"
        jeans.createdAt = createdAt
        jeans.purchasePrice = Decimal(80)
        jeans.purchaseCurrency = "USD"

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        try await store.saveGarment(jeans)
        let wear = StubWearEvent(id: UUID(), garmentIds: [jeans.id], wornOn: Date(timeIntervalSince1970: 1_725_500_000))
        try await store.saveWearEvent(wear)
        let savedLook = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: jeans.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "jeans as a top",
            offlineCached: true
        )
        try await store.saveOutfit(savedLook)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = savedLook
        model.outfitWearable = true
        let engineBefore = model.engineWorkGenerationForTests
        XCTAssertEqual(model.wearCount(for: jeans.id), 1)

        let ok = try await completeEdit(
            model,
            jeans,
            name: "Jeans",
            slot: .bottom,
            color: StubColorPrimary(family: "indigo", hex: "#3F4C7A", name: "Indigo"),
            pattern: jeans.pattern ?? "SOLID",
            surface: jeans.surface ?? "SMOOTH",
            formality: jeans.formality,
            warmth: jeans.warmth
        )
        XCTAssertTrue(ok)

        let edited = try XCTUnwrap(model.garments.first { $0.id == jeans.id })
        XCTAssertEqual(model.garments.count, 1)
        XCTAssertEqual(edited.id, jeans.id)
        XCTAssertEqual(edited.displayName, "Jeans")
        XCTAssertEqual(edited.slot, .bottom)
        XCTAssertEqual(edited.slot.displayLabel, "Bottom")
        XCTAssertEqual(edited.imagePath, "images/synthetic_jeans.svg")
        XCTAssertEqual(edited.purchasePrice, Decimal(80))
        XCTAssertEqual(edited.purchaseCurrency, "USD")
        XCTAssertEqual(edited.createdAt, createdAt)
        XCTAssertEqual(edited.attributeSource["slot"], "USER")
        XCTAssertEqual(edited.attributeSource["color"], "USER")
        XCTAssertEqual(model.wearCount(for: jeans.id), 1)
        XCTAssertEqual(model.wearHistory(for: jeans.id).map(\.id), [wear.id])
        XCTAssertNil(model.outfit, "slot change must drop the in-session board look")
        XCTAssertFalse(model.outfitWearable)
        XCTAssertNotEqual(model.engineWorkGenerationForTests, engineBefore)

        let storedLooks = await store.fetchOutfits()
        XCTAssertEqual(storedLooks.count, 1)
        XCTAssertEqual(storedLooks.first?.id, savedLook.id)
        XCTAssertEqual(storedLooks.first?.assignments.compactMap(\.garmentId), [jeans.id])
        let storedWears = await store.fetchWearEvents()
        XCTAssertEqual(storedWears.map(\.id), [wear.id])
        XCTAssertEqual(storedWears.first?.garmentIds, [jeans.id])
        XCTAssertNil(storedWears.first?.voidedAt)

        let lateAccepted = await model.applyLateEngineOutfitIfCurrent(
            savedLook,
            capturedEngineGeneration: engineBefore,
            capturedDataGeneration: store.dataGeneration
        )
        XCTAssertFalse(lateAccepted, "late generate must not persist after a slot edit")
        XCTAssertNil(model.outfit)
        let looksAfterLate = await store.fetchOutfits()
        XCTAssertEqual(looksAfterLate.map(\.id), [savedLook.id])

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunchStore = SwiftDataPersistenceStore(container: try XCTUnwrap(alive), defaults: defaults)
        let relaunched = await relaunchStore.fetchGarments()
        XCTAssertEqual(relaunched.count, 1, "relaunch must not duplicate the corrected garment")
        let persisted = try XCTUnwrap(relaunched.first)
        XCTAssertEqual(persisted.id, jeans.id)
        XCTAssertEqual(persisted.displayName, "Jeans")
        XCTAssertEqual(persisted.slot, .bottom)
        XCTAssertEqual(persisted.imagePath, "images/synthetic_jeans.svg")
        XCTAssertEqual(persisted.purchasePrice, Decimal(80))
        XCTAssertEqual(persisted.attributeSource["slot"], "USER")
        let relaunchLooks = await relaunchStore.fetchOutfits()
        let relaunchWears = await relaunchStore.fetchWearEvents()
        XCTAssertEqual(relaunchLooks.map(\.id), [savedLook.id])
        XCTAssertEqual(relaunchWears.map(\.id), [wear.id])
        alive = nil
    }

    @MainActor
    func testUnchangedReadinessSaveDoesNotClearBoardOrBumpGenerate() async throws {
        let jeans = disposableReadyGarment(name: "Jeans", slot: .top)
        let store = InMemoryPersistenceStore(garments: [jeans], sets: [], defaults: defaults)
        let look = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: jeans.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "keep board",
            offlineCached: false
        )
        try await store.saveOutfit(look)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = look
        model.outfitWearable = true
        let engineBefore = model.engineWorkGenerationForTests

        let ok = try await completeEdit(
            model,
            jeans,
            name: jeans.displayName,
            slot: .top,
            color: jeans.colorPrimary ?? StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: jeans.pattern ?? "SOLID",
            surface: jeans.surface ?? "SMOOTH",
            formality: jeans.formality,
            warmth: jeans.warmth
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(model.engineWorkGenerationForTests, engineBefore)
        XCTAssertEqual(model.outfit?.id, look.id)
        XCTAssertTrue(model.outfitWearable)
        let keptLooks = await store.fetchOutfits()
        XCTAssertEqual(keptLooks.map(\.id), [look.id])
    }

    // MARK: - 6 / 7. Upgrade existing #215 fixture

    @MainActor
    func testMigratedFixtureEditLeavesOtherCountsUnchanged() async throws {
        let working = try TestModelContainers.makeFromLegacyFixture(.seededWardrobe)
        var alive: ModelContainer? = working.container
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: working.cleanupRoot)
        }

        let store = SwiftDataPersistenceStore(container: working.container, defaults: defaults)
        let beforeGarments = await store.fetchGarments()
        let beforeWears = await store.fetchWearEvents()
        let beforeSets = await store.fetchSets()
        let beforeProfiles = await store.fetchAllStyleProfiles()
        XCTAssertFalse(beforeGarments.isEmpty)
        XCTAssertEqual(beforeWears.count, 1)

        let target = try XCTUnwrap(beforeGarments.first { $0.id != LegacyStoreFixtures.FixedIDs.photoGarment })
        let othersBefore = beforeGarments.filter { $0.id != target.id }
        var edited = target
        edited.displayName = "Edited Upgrade Piece"
        edited.displayNameSource = "USER"
        edited.attributeSource["color"] = "USER"
        try await store.saveGarment(edited)

        let afterGarments = await store.fetchGarments()
        let afterWears = await store.fetchWearEvents()
        let afterSets = await store.fetchSets()
        let afterProfiles = await store.fetchAllStyleProfiles()
        XCTAssertEqual(afterGarments.count, beforeGarments.count)
        XCTAssertEqual(afterWears.count, beforeWears.count)
        XCTAssertEqual(afterSets.count, beforeSets.count)
        XCTAssertEqual(afterProfiles.count, beforeProfiles.count)
        XCTAssertEqual(
            afterGarments.filter { $0.id != target.id }.map(\.id).sorted { $0.uuidString < $1.uuidString },
            othersBefore.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
        let persisted = try XCTUnwrap(afterGarments.first { $0.id == target.id })
        XCTAssertEqual(persisted.displayName, "Edited Upgrade Piece")
        XCTAssertEqual(persisted.imagePath, target.imagePath)
        XCTAssertEqual(persisted.attributeSource["color"], "USER")

        alive = try TestModelContainers.restartMigrated(storeURL: working.storeURL, releasing: working.container)
        let relaunchStore = SwiftDataPersistenceStore(container: try XCTUnwrap(alive), defaults: defaults)
        let relaunchGarments = await relaunchStore.fetchGarments()
        let relaunchWears = await relaunchStore.fetchWearEvents()
        XCTAssertEqual(relaunchGarments.count, beforeGarments.count)
        XCTAssertEqual(relaunchWears.count, beforeWears.count)
        let relaunchEdited = try XCTUnwrap(relaunchGarments.first { $0.id == target.id })
        XCTAssertEqual(relaunchEdited.displayName, "Edited Upgrade Piece")
        alive = nil
    }

    // MARK: - Helpers

    private func disposableReadyGarment(
        name: String = "Edit Tee",
        slot: StubSlot = .top,
        setId: UUID? = nil
    ) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: "images/synthetic_edit.svg",
            formality: 3,
            warmth: 3,
            setId: setId,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @MainActor
    private func completeEdit(
        _ model: LoopDemoModel,
        _ garment: StubGarment,
        name: String,
        slot: StubSlot,
        color: StubColorPrimary,
        pattern: String,
        surface: String,
        formality: Int?,
        warmth: Int?
    ) async throws -> Bool {
        await model.completeReadiness(
            id: garment.id,
            slot: slot,
            displayName: name,
            displayNameIsUserSet: true,
            color: color,
            pattern: pattern,
            surface: surface,
            formality: formality,
            warmth: warmth,
            requireComplete: true
        )
    }
}
