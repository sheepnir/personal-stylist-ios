import XCTest
@testable import PersonalStylist

/// #279 colour editor: unknown/custom values stay selected and persist unless a catalog family is picked.
final class FinishDetailsColorDraftTests: XCTestCase {
    private let custom = StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
    private let customOnNavyHex = StubColorPrimary(family: "forest", hex: "#1B2A4A", name: "Forest Moss")
    private let navy = StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy")
    private let navyNamed = StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Midnight")

    func testKnownFamilySeedsExactValuesAndStaysReady() {
        let seeded = FinishDetailsColorDraft.seed(from: navy)
        XCTAssertEqual(seeded.familyId, "navy")
        XCTAssertEqual(seeded.hex, "#1B2A4A")
        XCTAssertEqual(seeded.displayName, "Navy")
        XCTAssertFalse(seeded.isCustom)
        XCTAssertFalse(FinishDetailsColorDraft.missingColor(seeded))
        XCTAssertEqual(FinishDetailsColorDraft.persistColor(from: seeded), navy)
    }

    func testKnownFamilyWithCustomNamePreservesFamilyAndHex() {
        let seeded = FinishDetailsColorDraft.seed(from: navyNamed)
        let renamed = FinishDetailsColorDraft.editingName("Ink Navy", previous: seeded)
        XCTAssertEqual(renamed.familyId, "navy")
        XCTAssertEqual(renamed.hex, "#1B2A4A")
        XCTAssertEqual(renamed.displayName, "Ink Navy")
        let persisted = FinishDetailsColorDraft.persistColor(from: renamed)
        XCTAssertEqual(persisted.family, "navy")
        XCTAssertEqual(persisted.hex, "#1B2A4A")
        XCTAssertEqual(persisted.name, "Ink Navy")
    }

    func testUnknownFamilyOpensSelectedAndRemainsReady() {
        let seeded = FinishDetailsColorDraft.seed(from: custom)
        XCTAssertTrue(seeded.isCustom)
        XCTAssertTrue(seeded.hasColor)
        XCTAssertFalse(FinishDetailsColorDraft.missingColor(seeded))
        XCTAssertEqual(seeded.familyId, "forest")
        XCTAssertEqual(seeded.hex, "#2D5A3D")
        XCTAssertEqual(seeded.displayName, "Forest Moss")
        XCTAssertEqual(seeded.accessibilityLabel, "Forest Moss")
        XCTAssertEqual(FinishDetailsColorDraft.persistColor(from: seeded), custom)
        XCTAssertEqual(FinishDetailsColorDraft.previewColor(from: seeded), custom)
    }

    func testUnknownFamilyWithCatalogHexIsNotRemapped() {
        XCTAssertEqual(
            ColorFamilyCatalog.match(family: "forest", name: "Forest Moss", hex: "#1B2A4A")?.id,
            "navy",
            "wardrobe swatch match may still resolve hex; editor seed must not"
        )
        let seeded = FinishDetailsColorDraft.seed(from: customOnNavyHex)
        XCTAssertEqual(seeded.familyId, "forest")
        XCTAssertEqual(seeded.hex, "#1B2A4A")
        XCTAssertEqual(seeded.displayName, "Forest Moss")
        XCTAssertTrue(seeded.isCustom)
        XCTAssertEqual(FinishDetailsColorDraft.persistColor(from: seeded), customOnNavyHex)
    }

    func testEditingOnlyCustomNamePreservesFamilyAndHex() {
        let seeded = FinishDetailsColorDraft.seed(from: custom)
        let renamed = FinishDetailsColorDraft.editingName("Deep Forest", previous: seeded)
        XCTAssertEqual(renamed.familyId, "forest")
        XCTAssertEqual(renamed.hex, "#2D5A3D")
        XCTAssertEqual(renamed.displayName, "Deep Forest")
        let persisted = FinishDetailsColorDraft.persistColor(from: renamed)
        XCTAssertEqual(persisted.family, "forest")
        XCTAssertEqual(persisted.hex, "#2D5A3D")
        XCTAssertEqual(persisted.name, "Deep Forest")
    }

    func testChoosingCatalogFamilyReplacesCustomWithCanonicalValues() throws {
        let seeded = FinishDetailsColorDraft.seed(from: custom)
        let navyOption = try XCTUnwrap(ColorFamilyCatalog.all.first(where: { $0.id == "navy" }))
        let picked = FinishDetailsColorDraft.selectingCatalog(navyOption)
        XCTAssertEqual(picked.familyId, "navy")
        XCTAssertEqual(picked.hex, "#1B2A4A")
        XCTAssertEqual(picked.displayName, "Navy")
        XCTAssertFalse(picked.isCustom)
        XCTAssertNotEqual(picked, seeded)
        XCTAssertEqual(FinishDetailsColorDraft.persistColor(from: picked), navy)
    }

    func testNameOnlyDoesNotSatisfyRequiredColor() {
        let nameOnly = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: nil, hex: nil, name: "Forest Moss")
        )
        XCTAssertEqual(nameOnly.displayName, "Forest Moss")
        XCTAssertTrue(nameOnly.familyId.isEmpty)
        XCTAssertTrue(nameOnly.hex.isEmpty)
        XCTAssertFalse(nameOnly.hasColor)
        XCTAssertFalse(nameOnly.isCustom)
        XCTAssertTrue(FinishDetailsColorDraft.missingColor(nameOnly))
        XCTAssertNil(FinishDetailsColorDraft.previewColor(from: nameOnly))

        let typed = FinishDetailsColorDraft.editingName(
            "Forest Moss",
            previous: FinishDetailsColorDraft.seed(from: nil)
        )
        XCTAssertTrue(FinishDetailsColorDraft.missingColor(typed))
        XCTAssertFalse(typed.hasColor)
        XCTAssertNil(FinishDetailsColorDraft.previewColor(from: typed))
        XCTAssertFalse(
            FinishDetailsColorDraft.hasSwatchIdentity(
                FinishDetailsColorDraft.persistColor(from: typed)
            )
        )
    }

    func testHexOnlySatisfiesRequiredColorAndPersists() {
        let hexOnly = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: nil, hex: "#2D5A3D", name: nil)
        )
        XCTAssertTrue(hexOnly.hasColor)
        XCTAssertTrue(hexOnly.isCustom)
        XCTAssertFalse(FinishDetailsColorDraft.missingColor(hexOnly))
        let persisted = FinishDetailsColorDraft.persistColor(from: hexOnly)
        XCTAssertNil(persisted.family)
        XCTAssertEqual(persisted.hex, "#2D5A3D")
        XCTAssertNil(persisted.name)
    }

    func testEmptyColourIsMissingAndCancelLeavesSeededSnapshot() {
        let empty = FinishDetailsColorDraft.seed(from: nil)
        XCTAssertTrue(FinishDetailsColorDraft.missingColor(empty))
        XCTAssertFalse(empty.hasColor)
        XCTAssertNil(FinishDetailsColorDraft.previewColor(from: empty))

        let seeded = FinishDetailsSnapshot(
            slot: .top,
            name: "Canvas Tee",
            colorFamilyId: "forest",
            colorHex: "#2D5A3D",
            colorDisplayName: "Forest Moss",
            pattern: "SOLID",
            surface: "SMOOTH",
            formality: 3,
            warmth: 3,
            priceText: "",
            currency: "USD",
            includePurchaseDate: false,
            purchaseDate: Date(timeIntervalSince1970: 1_725_000_000),
            priorWearBucket: ""
        )
        var dirty = seeded
        dirty.colorDisplayName = "Should Not Persist"
        dirty.colorFamilyId = "navy"
        dirty.colorHex = "#1B2A4A"
        XCTAssertTrue(FinishDetailsDraft.isDirty(seeded: seeded, current: dirty))
        XCTAssertFalse(FinishDetailsDraft.discardWritesToStore())
        XCTAssertEqual(FinishDetailsDraft.snapshotAfterDiscard(seeded: seeded), seeded)
    }
}
