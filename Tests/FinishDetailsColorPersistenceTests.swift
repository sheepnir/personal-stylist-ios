import XCTest
import SwiftData
@testable import PersonalStylist

/// #279 — colour family/hex/name survive on-disk relaunch. Disposable temp stores only.
final class FinishDetailsColorPersistenceTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "FinishDetailsColorPersistenceTests.\(UUID().uuidString)"
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

    @MainActor
    func testKnownFamilyPersistsExactValuesThroughRelaunch() async throws {
        let navy = StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy")
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        var garment = disposableReadyGarment(color: navy)
        garment.purchasePrice = Decimal(45)
        garment.purchaseCurrency = "USD"
        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        try await store.saveGarment(garment)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let seeded = FinishDetailsColorDraft.seed(from: navy)
        XCTAssertEqual(FinishDetailsColorDraft.persistColor(from: seeded), navy)
        let saved = await model.completeReadiness(
            id: garment.id,
            color: FinishDetailsColorDraft.persistColor(from: seeded),
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            requireComplete: true
        )
        XCTAssertTrue(saved)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunchStore = SwiftDataPersistenceStore(container: try XCTUnwrap(alive), defaults: defaults)
        let relaunched = await relaunchStore.fetchGarments()
        let persisted = try XCTUnwrap(relaunched.first { $0.id == garment.id })
        XCTAssertEqual(persisted.colorPrimary?.family, "navy")
        XCTAssertEqual(persisted.colorPrimary?.hex, "#1B2A4A")
        XCTAssertEqual(persisted.colorPrimary?.name, "Navy")
        XCTAssertEqual(persisted.slot, .top)
        XCTAssertEqual(persisted.purchasePrice, Decimal(45))
        XCTAssertEqual(persisted.purchaseCurrency, "USD")
        alive = nil
    }

    @MainActor
    func testUnknownCustomColourStaysReadyAndSurvivesRelaunch() async throws {
        let custom = StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let garment = disposableReadyGarment(color: custom)
        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        try await store.saveGarment(garment)

        let seeded = FinishDetailsColorDraft.seed(from: custom)
        XCTAssertTrue(seeded.isCustom)
        XCTAssertFalse(FinishDetailsColorDraft.missingColor(seeded))

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let saved = await model.completeReadiness(
            id: garment.id,
            color: FinishDetailsColorDraft.persistColor(from: seeded),
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            requireComplete: true
        )
        XCTAssertTrue(saved)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunchStore = SwiftDataPersistenceStore(container: try XCTUnwrap(alive), defaults: defaults)
        let relaunched = await relaunchStore.fetchGarments()
        let persisted = try XCTUnwrap(relaunched.first { $0.id == garment.id })
        XCTAssertEqual(persisted.colorPrimary?.family, "forest")
        XCTAssertEqual(persisted.colorPrimary?.hex, "#2D5A3D")
        XCTAssertEqual(persisted.colorPrimary?.name, "Forest Moss")
        XCTAssertEqual(persisted.readiness, .ready)
        alive = nil
    }

    @MainActor
    func testEditingOnlyCustomNamePreservesFamilyHexSlotAndPrice() async throws {
        let custom = StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        let store = InMemoryPersistenceStore(
            garments: [disposableReadyGarment(color: custom, price: Decimal(18))],
            sets: [],
            defaults: defaults
        )
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let garment = try XCTUnwrap(model.garments.first)
        let beforeSlot = garment.slot
        let beforePrice = garment.purchasePrice

        let renamed = FinishDetailsColorDraft.editingName(
            "Deep Forest",
            previous: FinishDetailsColorDraft.seed(from: garment.colorPrimary)
        )
        let saved = await model.completeReadiness(
            id: garment.id,
            color: FinishDetailsColorDraft.persistColor(from: renamed),
            pattern: garment.pattern ?? "SOLID",
            surface: garment.surface ?? "SMOOTH",
            formality: garment.formality,
            warmth: garment.warmth,
            requireComplete: true
        )
        XCTAssertTrue(saved)
        let after = try XCTUnwrap(model.garments.first { $0.id == garment.id })
        XCTAssertEqual(after.colorPrimary?.family, "forest")
        XCTAssertEqual(after.colorPrimary?.hex, "#2D5A3D")
        XCTAssertEqual(after.colorPrimary?.name, "Deep Forest")
        XCTAssertEqual(after.slot, beforeSlot)
        XCTAssertEqual(after.purchasePrice, beforePrice)
        XCTAssertEqual(after.imagePath, garment.imagePath)
    }

    @MainActor
    func testHexOnlyReadyAndDraftSaveKeepHex() async throws {
        let hexOnly = StubColorPrimary(family: nil, hex: "#2D5A3D", name: nil)
        let store = InMemoryPersistenceStore(
            garments: [disposableReadyGarment(color: hexOnly)],
            sets: [],
            defaults: defaults
        )
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let garment = try XCTUnwrap(model.garments.first)
        let color = FinishDetailsColorDraft.persistColor(
            from: FinishDetailsColorDraft.seed(from: hexOnly)
        )

        let readySaved = await model.completeReadiness(
            id: garment.id,
            color: color,
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            requireComplete: true
        )
        XCTAssertTrue(readySaved)
        XCTAssertEqual(model.garments.first?.colorPrimary?.hex, "#2D5A3D")

        let draftSaved = await model.completeReadiness(
            id: garment.id,
            color: color,
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            requireComplete: false
        )
        XCTAssertTrue(draftSaved)
        XCTAssertEqual(model.garments.first?.colorPrimary?.hex, "#2D5A3D")
        XCTAssertNil(model.garments.first?.colorPrimary?.family)
    }

    @MainActor
    func testNameOnlyDoesNotReadySave() async throws {
        let navy = StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy")
        let nameOnly = StubColorPrimary(family: nil, hex: nil, name: "Forest Moss")
        let store = InMemoryPersistenceStore(
            garments: [disposableReadyGarment(color: navy)],
            sets: [],
            defaults: defaults
        )
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let garment = try XCTUnwrap(model.garments.first)
        XCTAssertFalse(FinishDetailsColorDraft.hasSwatchIdentity(nameOnly))
        let saved = await model.completeReadiness(
            id: garment.id,
            color: nameOnly,
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            requireComplete: true
        )
        XCTAssertFalse(saved)
        XCTAssertEqual(model.garments.first?.colorPrimary, navy)
    }

    @MainActor
    func testChoosingCatalogFamilyReplacesCustomOnDisk() async throws {
        let custom = StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        let navyOption = try XCTUnwrap(ColorFamilyCatalog.all.first(where: { $0.id == "navy" }))
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let garment = disposableReadyGarment(color: custom)
        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        try await store.saveGarment(garment)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        let picked = FinishDetailsColorDraft.selectingCatalog(navyOption)
        let saved = await model.completeReadiness(
            id: garment.id,
            color: FinishDetailsColorDraft.persistColor(from: picked),
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            requireComplete: true
        )
        XCTAssertTrue(saved)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunchStore = SwiftDataPersistenceStore(container: try XCTUnwrap(alive), defaults: defaults)
        let relaunched = await relaunchStore.fetchGarments()
        let persisted = try XCTUnwrap(relaunched.first { $0.id == garment.id })
        XCTAssertEqual(persisted.colorPrimary?.family, "navy")
        XCTAssertEqual(persisted.colorPrimary?.hex, "#1B2A4A")
        XCTAssertEqual(persisted.colorPrimary?.name, "Navy")
        alive = nil
    }

    @MainActor
    func testCancelWritesNothingToStore() async throws {
        let custom = StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        let garment = disposableReadyGarment(color: custom)
        let store = InMemoryPersistenceStore(garments: [garment], sets: [], defaults: defaults)
        let before = await store.fetchGarments()
        let seeded = FinishDetailsColorDraft.seed(from: custom)
        var dirty = seeded
        dirty.displayName = "Should Not Persist"
        dirty.familyId = "navy"
        dirty.hex = "#1B2A4A"
        XCTAssertTrue(FinishDetailsDraft.isDirty(
            seeded: FinishDetailsSnapshot(
                slot: .top,
                name: garment.displayName,
                colorFamilyId: seeded.familyId,
                colorHex: seeded.hex,
                colorDisplayName: seeded.displayName,
                pattern: "SOLID",
                surface: "SMOOTH",
                formality: 3,
                warmth: 3,
                priceText: "",
                currency: "USD",
                includePurchaseDate: false,
                purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
                priorWearBucket: ""
            ),
            current: FinishDetailsSnapshot(
                slot: .top,
                name: garment.displayName,
                colorFamilyId: dirty.familyId,
                colorHex: dirty.hex,
                colorDisplayName: dirty.displayName,
                pattern: "SOLID",
                surface: "SMOOTH",
                formality: 3,
                warmth: 3,
                priceText: "",
                currency: "USD",
                includePurchaseDate: false,
                purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
                priorWearBucket: ""
            )
        ))
        XCTAssertFalse(FinishDetailsDraft.discardWritesToStore())
        let after = await store.fetchGarments()
        XCTAssertEqual(after.first?.colorPrimary, before.first?.colorPrimary)
        XCTAssertEqual(after.first?.displayName, before.first?.displayName)
        XCTAssertEqual(after.first?.slot, before.first?.slot)
    }

    private func disposableReadyGarment(
        color: StubColorPrimary,
        price: Decimal? = nil
    ) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: "Canvas Colour Tee",
            slot: .top,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: color,
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: "images/synthetic_colour.svg",
            formality: 3,
            warmth: 3,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            purchasePrice: price,
            purchaseCurrency: price == nil ? nil : "USD"
        )
    }
}
