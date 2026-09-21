import Foundation

/// D-72 / #120 Edit garment copy — never raw enums, HTTP, or persistence tokens.
enum GarmentEditCopy {
    static let title = "Edit garment"
    static let nameAndCategory = "Name and category"
    static let slotLabel = "Slot"
    static let nameField = "Name"
    static let nameAccessibility = "Garment name"
    static let saveChanges = "Save changes"
    static let save = "Save"
    static let saveAsDraft = "Save as draft"
    static let cancel = "Cancel"
    static let discardTitle = "Discard changes?"
    static let discardAction = "Discard"
    static let keepEditing = "Keep editing"
    static let discardMessage =
        "These edits have not been saved. Discard them to leave this piece as it is."
    static let slotChangeFootnote =
        "This piece keeps its identity, photo, price, and wear history. Saved looks that include it stay. Outfit generation in this session will refresh after you save."
    static let editSheetFootnote =
        "This piece stays in the wardrobe. Cancel leaves it as-is. Save changes updates it when every required field is set. Save as draft stays out of outfit generation until every required field is set."

    static func navigationTitle(mode: FinishDetailsMode, finishDetailsTitle: String) -> String {
        switch mode {
        case .editGarment:
            return title
        case .finishDetails, .cameraIntake:
            return finishDetailsTitle
        }
    }

    static func titleAccessibility(mode: FinishDetailsMode, finishDetailsTitle: String) -> String {
        navigationTitle(mode: mode, finishDetailsTitle: finishDetailsTitle)
    }

    static func identitySectionHeader(mode: FinishDetailsMode) -> String {
        switch mode {
        case .editGarment, .cameraIntake:
            return nameAndCategory
        case .finishDetails:
            return "Identity"
        }
    }

    static func primarySaveTitle(mode: FinishDetailsMode) -> String {
        switch mode {
        case .editGarment:
            return saveChanges
        case .finishDetails, .cameraIntake:
            return save
        }
    }

    static let savingHint = "Saving. Wait until it finishes."
    static let saveReadyHint = "Marks this piece ready to use in outfits."
    static let saveDraftHint = "Keeps this as a draft. It stays out of outfit generation."
    static let slotRequiredHint = "Choose a slot before saving."
    static let selectedValue = "Selected"
    static let notSelectedValue = "Not selected"

    static func requiredFieldsLine(_ missing: [String]) -> String {
        "Required to use in outfits: \(missing.joined(separator: ", "))."
    }

    static func saveAccessibilityHint(
        canMarkReady: Bool,
        isSaving: Bool,
        missingRequiredFields: [String],
        hasRequiredSlot: Bool
    ) -> String {
        if isSaving { return savingHint }
        if !hasRequiredSlot { return slotRequiredHint }
        if !canMarkReady { return requiredFieldsLine(missingRequiredFields) }
        return saveReadyHint
    }

    static func saveAsDraftAccessibilityHint(canSaveDraft: Bool, isSaving: Bool, hasRequiredSlot: Bool) -> String {
        if isSaving { return savingHint }
        if !hasRequiredSlot || !canSaveDraft { return slotRequiredHint }
        return saveDraftHint
    }

    static func containsMachineToken(_ text: String) -> Bool {
        let forbidden = [
            "HTTP", "http://", "https://", "NSURL", "token",
            "attributeSource", "GarmentEntity", "hasSwatchIdentity",
            "colorFamilyId", "NSError", "Error.description",
        ]
        return forbidden.contains { text.contains($0) }
    }
}
