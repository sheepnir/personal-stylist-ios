import XCTest
@testable import PersonalStylist

/// #280 Finish details VoiceOver contracts. Colour needs family or hex (D-74 / #279).
final class FinishDetailsA11yContractTests: XCTestCase {
    func testSaveDisabledHintSpeaksMissingColorWhenNameOnly() {
        let nameOnly = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: nil, hex: nil, name: "Forest Moss")
        )
        XCTAssertTrue(FinishDetailsColorDraft.missingColor(nameOnly))
        XCTAssertFalse(
            FinishDetailsColorDraft.hasSwatchIdentity(
                FinishDetailsColorDraft.persistColor(from: nameOnly)
            )
        )

        let hint = GarmentEditCopy.saveAccessibilityHint(
            canMarkReady: false,
            isSaving: false,
            missingRequiredFields: ["Color", "Pattern"],
            hasRequiredSlot: true
        )
        XCTAssertEqual(hint, "Required to use in outfits: Color, Pattern.")
        XCTAssertTrue(hint.contains("Color"))
        XCTAssertFalse(hint.contains("#"))
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(hint))
    }

    func testHexOrFamilySatisfiesColorAndSaveHintStaysHuman() {
        let hexOnly = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: nil, hex: "#2D5A3D", name: nil)
        )
        XCTAssertFalse(FinishDetailsColorDraft.missingColor(hexOnly))
        XCTAssertTrue(FinishDetailsColorDraft.hasSwatchIdentity(FinishDetailsColorDraft.persistColor(from: hexOnly)))
        XCTAssertEqual(hexOnly.accessibilityLabel, "Custom colour")

        let ready = GarmentEditCopy.saveAccessibilityHint(
            canMarkReady: true,
            isSaving: false,
            missingRequiredFields: [],
            hasRequiredSlot: true
        )
        XCTAssertEqual(ready, GarmentEditCopy.saveReadyHint)
        XCTAssertEqual(
            GarmentEditCopy.saveAccessibilityHint(
                canMarkReady: true,
                isSaving: true,
                missingRequiredFields: [],
                hasRequiredSlot: true
            ),
            GarmentEditCopy.savingHint
        )
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(ready))
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(GarmentEditCopy.savingHint))
    }

    func testSaveAsDraftDisabledHintSpeaksMissingSlot() {
        XCTAssertEqual(
            GarmentEditCopy.saveAsDraftAccessibilityHint(
                canSaveDraft: false,
                isSaving: false,
                hasRequiredSlot: false
            ),
            GarmentEditCopy.slotRequiredHint
        )
        XCTAssertEqual(
            GarmentEditCopy.saveAsDraftAccessibilityHint(
                canSaveDraft: true,
                isSaving: false,
                hasRequiredSlot: true
            ),
            GarmentEditCopy.saveDraftHint
        )
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(GarmentEditCopy.slotRequiredHint))
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(GarmentEditCopy.saveDraftHint))
    }

    func testColourSelectionUsesSpokenLabelNotColourAlone() throws {
        let navy = try XCTUnwrap(ColorFamilyCatalog.all.first(where: { $0.id == "navy" }))
        let selected = FinishDetailsColorDraft.selectingCatalog(navy)
        XCTAssertEqual(selected.accessibilityLabel, "Navy")
        XCTAssertNotEqual(selected.accessibilityLabel, navy.hex)
        XCTAssertEqual(GarmentEditCopy.selectedValue, "Selected")
        XCTAssertEqual(GarmentEditCopy.notSelectedValue, "Not selected")
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(selected.accessibilityLabel))
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(GarmentEditCopy.selectedValue))

        let custom = FinishDetailsColorDraft.seed(
            from: StubColorPrimary(family: "forest", hex: "#2D5A3D", name: "Forest Moss")
        )
        XCTAssertEqual(custom.accessibilityLabel, "Forest Moss")
        XCTAssertTrue(custom.isCustom)
    }

    func testFailureCopyHasNoMachineTokens() {
        let missing = GarmentEditCopy.requiredFieldsLine(["Color", "Warmth"])
        XCTAssertFalse(GarmentEditCopy.containsMachineToken(missing))
        XCTAssertFalse(GarmentEditCopy.containsMachineToken("Couldn’t save — try again."))
        XCTAssertFalse(GarmentEditCopy.containsMachineToken("Fill every required field to mark ready."))
    }
}
