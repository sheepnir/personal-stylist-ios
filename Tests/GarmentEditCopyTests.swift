import XCTest
@testable import PersonalStylist

/// D-72 / #120 Edit garment copy + dirty/cancel semantics.
/// Disposable in-memory fixtures only. Cancel / discard never write the store.
final class GarmentEditCopyTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "GarmentEditCopyTests.\(UUID().uuidString)"
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

    func testEditGarmentTitleAndSaveCopyAreExact() {
        XCTAssertEqual(GarmentEditCopy.title, "Edit garment")
        XCTAssertEqual(
            GarmentEditCopy.navigationTitle(mode: .editGarment, finishDetailsTitle: "Canvas Coat"),
            "Edit garment"
        )
        XCTAssertEqual(
            GarmentEditCopy.titleAccessibility(mode: .editGarment, finishDetailsTitle: "Canvas Coat"),
            "Edit garment"
        )
        XCTAssertEqual(GarmentEditCopy.nameAndCategory, "Name and category")
        XCTAssertEqual(GarmentEditCopy.identitySectionHeader(mode: .editGarment), "Name and category")
        XCTAssertEqual(GarmentEditCopy.slotLabel, "Slot")
        XCTAssertEqual(GarmentEditCopy.saveChanges, "Save changes")
        XCTAssertEqual(GarmentEditCopy.primarySaveTitle(mode: .editGarment), "Save changes")
        XCTAssertNotEqual(GarmentEditCopy.primarySaveTitle(mode: .editGarment), "Save")
    }

    func testEditPresentationUsesEditGarmentChromeAndHidesNextDraftQueue() {
        let jeansId = UUID()
        let presentation = FinishDetailsPresentation.edit(garmentId: jeansId)
        XCTAssertEqual(presentation.garmentId, jeansId)
        XCTAssertEqual(presentation.mode, .editGarment)
        XCTAssertEqual(
            GarmentEditCopy.navigationTitle(mode: presentation.mode, finishDetailsTitle: "Canvas jeans"),
            "Edit garment"
        )
        XCTAssertEqual(GarmentEditCopy.identitySectionHeader(mode: presentation.mode), "Name and category")
        XCTAssertEqual(GarmentEditCopy.primarySaveTitle(mode: presentation.mode), "Save changes")
        XCTAssertFalse(FinishDetailsDraft.showsNextDraftQueue(mode: presentation.mode))
    }

    func testFinishPresentationUsesFinishDetailsChromeAndAllowsQueue() {
        let jeansId = UUID()
        let presentation = FinishDetailsPresentation.finish(garmentId: jeansId)
        XCTAssertEqual(presentation.garmentId, jeansId)
        XCTAssertEqual(presentation.mode, .finishDetails)
        XCTAssertEqual(
            GarmentEditCopy.navigationTitle(mode: presentation.mode, finishDetailsTitle: "Canvas jeans"),
            "Canvas jeans"
        )
        XCTAssertEqual(GarmentEditCopy.identitySectionHeader(mode: presentation.mode), "Identity")
        XCTAssertEqual(GarmentEditCopy.primarySaveTitle(mode: presentation.mode), "Save")
        XCTAssertTrue(FinishDetailsDraft.showsNextDraftQueue(mode: presentation.mode))
    }

    func testFinishDetailsModeKeepsExistingSaveTitle() {
        XCTAssertEqual(
            GarmentEditCopy.navigationTitle(mode: .finishDetails, finishDetailsTitle: "Finish details"),
            "Finish details"
        )
        XCTAssertEqual(GarmentEditCopy.primarySaveTitle(mode: .finishDetails), "Save")
        XCTAssertEqual(GarmentEditCopy.identitySectionHeader(mode: .finishDetails), "Identity")
        XCTAssertEqual(GarmentEditCopy.saveAsDraft, "Save as draft")
        XCTAssertTrue(FinishDetailsDraft.showsNextDraftQueue(mode: .finishDetails))
        XCTAssertFalse(FinishDetailsDraft.showsNextDraftQueue(mode: .editGarment))
        XCTAssertTrue(FinishDetailsDraft.dismissesAfterSuccessfulSave(mode: .editGarment))
        XCTAssertFalse(FinishDetailsDraft.dismissesAfterSuccessfulSave(mode: .finishDetails))
    }

    func testSlotPickerUsesExistingDisplayLabels() {
        XCTAssertEqual(StubSlot.top.displayLabel, "Top")
        XCTAssertEqual(StubSlot.bottom.displayLabel, "Bottom")
        XCTAssertEqual(StubSlot.midLayer.displayLabel, "Mid layer")
        XCTAssertEqual(StubSlot.jacket.displayLabel, "Jacket")
        XCTAssertEqual(StubSlot.outerwear.displayLabel, "Outerwear")
        XCTAssertEqual(StubSlot.footwear.displayLabel, "Footwear")
        XCTAssertEqual(StubSlot.accessory.displayLabel, "Accessory")
        XCTAssertFalse(StubSlot.top.displayLabel.contains("TOP"))
        XCTAssertFalse(StubSlot.bottom.displayLabel.contains("BOTTOM"))
    }

    func testSlotChangeFootnoteKeepsIdentityAndDoesNotClaimLooksDeleted() {
        let note = GarmentEditCopy.slotChangeFootnote
        XCTAssertTrue(note.contains("identity"))
        XCTAssertTrue(note.contains("photo"))
        XCTAssertTrue(note.contains("price"))
        XCTAssertTrue(note.contains("wear history"))
        XCTAssertTrue(note.contains("Saved looks that include it stay"))
        XCTAssertTrue(note.contains("Outfit generation"))
        XCTAssertTrue(note.contains("refresh"))
        XCTAssertFalse(note.lowercased().contains("delete"))
        XCTAssertFalse(note.lowercased().contains("deleted"))
        XCTAssertFalse(note.contains("taxonomy"))

        let joined = [
            GarmentEditCopy.title,
            GarmentEditCopy.slotChangeFootnote,
            GarmentEditCopy.discardTitle,
            GarmentEditCopy.discardMessage,
            GarmentEditCopy.editSheetFootnote,
        ].joined(separator: "\n")
        for forbidden in [
            "HTTP", "http://", "https://", "NSURL", "token",
            "attributeSource", "completeReadiness", "GarmentEntity",
            "TOP", "BOTTOM", "READY", "DRAFT",
        ] {
            XCTAssertFalse(joined.contains(forbidden), "copy must not contain \(forbidden)")
        }
    }

    func testDiscardCopyNamesKeepEditing() {
        XCTAssertEqual(GarmentEditCopy.discardTitle, "Discard changes?")
        XCTAssertEqual(GarmentEditCopy.discardAction, "Discard")
        XCTAssertEqual(GarmentEditCopy.keepEditing, "Keep editing")
        XCTAssertEqual(GarmentEditCopy.cancel, "Cancel")
        XCTAssertTrue(GarmentEditCopy.discardMessage.contains("not been saved"))
    }

    // MARK: - Dirty / cancel

    func testSeededSnapshotIsNotDirtyAndCleanCancelDismisses() {
        let seeded = sampleSnapshot(slot: .top, name: "Canvas Jeans")
        XCTAssertFalse(FinishDetailsDraft.isDirty(seeded: seeded, current: seeded))
        XCTAssertEqual(FinishDetailsDraft.dismissDecision(isDirty: false), .dismiss)
        XCTAssertFalse(FinishDetailsDraft.shouldConfirmDismiss(isDirty: false))
        XCTAssertFalse(FinishDetailsDraft.blocksInteractiveDismiss(isDirty: false, isSaving: false))
        XCTAssertTrue(FinishDetailsDraft.blocksInteractiveDismiss(isDirty: false, isSaving: true))
    }

    func testSlotOrNameChangeIsDirtyAndBlocksInteractiveDismiss() {
        let seeded = sampleSnapshot(slot: .top, name: "Canvas Jeans")
        var slotChanged = seeded
        slotChanged.slot = .bottom
        XCTAssertTrue(FinishDetailsDraft.isDirty(seeded: seeded, current: slotChanged))
        XCTAssertTrue(FinishDetailsDraft.showsSlotChangeFootnote(selected: slotChanged.slot, saved: seeded.slot))
        XCTAssertFalse(FinishDetailsDraft.showsSlotChangeFootnote(selected: seeded.slot, saved: seeded.slot))
        XCTAssertEqual(FinishDetailsDraft.dismissDecision(isDirty: true), .confirmDiscard)
        XCTAssertTrue(FinishDetailsDraft.shouldConfirmDismiss(isDirty: true))
        XCTAssertTrue(FinishDetailsDraft.blocksInteractiveDismiss(isDirty: true, isSaving: false))

        var named = seeded
        named.name = "Ink Jeans"
        XCTAssertTrue(FinishDetailsDraft.isDirty(seeded: seeded, current: named))
        XCTAssertFalse(FinishDetailsDraft.showsSlotChangeFootnote(selected: named.slot, saved: seeded.slot))
    }

    func testDiscardKeepsSeededSnapshotAndWritesNothing() async throws {
        let jeans = disposableGarment(name: "Canvas Jeans", slot: .top)
        let store = InMemoryPersistenceStore(garments: [jeans], defaults: defaults)
        let before = await store.fetchGarments()
        XCTAssertEqual(before.map(\.slot), [.top])
        XCTAssertEqual(before.map(\.displayName), ["Canvas Jeans"])

        let seeded = sampleSnapshot(slot: jeans.slot, name: jeans.displayName)
        var dirty = seeded
        dirty.slot = .bottom
        dirty.name = "Should Not Persist"
        XCTAssertTrue(FinishDetailsDraft.isDirty(seeded: seeded, current: dirty))
        XCTAssertFalse(FinishDetailsDraft.discardWritesToStore())
        XCTAssertEqual(FinishDetailsDraft.snapshotAfterDiscard(seeded: seeded), seeded)
        XCTAssertEqual(FinishDetailsDraft.dismissDecision(isDirty: true), .confirmDiscard)

        let after = await store.fetchGarments()
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.map(\.slot), [.top])
        XCTAssertEqual(after.map(\.displayName), ["Canvas Jeans"])
        XCTAssertEqual(after.map(\.displayName), before.map(\.displayName))
    }

    func testCleanCancelLeavesStoreUnchanged() async throws {
        let jeans = disposableGarment(name: "Canvas Jeans", slot: .top)
        let store = InMemoryPersistenceStore(garments: [jeans], defaults: defaults)
        let before = await store.fetchGarments()
        XCTAssertEqual(FinishDetailsDraft.dismissDecision(isDirty: false), .dismiss)
        XCTAssertFalse(FinishDetailsDraft.discardWritesToStore())
        let after = await store.fetchGarments()
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.first?.slot, .top)
    }

    // MARK: - Helpers

    private func sampleSnapshot(slot: StubSlot, name: String) -> FinishDetailsSnapshot {
        FinishDetailsSnapshot(
            slot: slot,
            name: name,
            colorFamilyId: "navy",
            colorHex: "#1B2A4A",
            colorDisplayName: "Navy",
            pattern: "SOLID",
            surface: "RUGGED",
            formality: 2,
            warmth: 3,
            priceText: "",
            currency: "USD",
            includePurchaseDate: false,
            purchaseDate: Date(timeIntervalSince1970: 1_725_000_000),
            priorWearBucket: ""
        )
    }

    private func disposableGarment(name: String, slot: StubSlot) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "RUGGED",
            imagePath: nil,
            formality: 2,
            warmth: 3,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
    }
}
