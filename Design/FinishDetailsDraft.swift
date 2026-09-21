import Foundation

enum FinishDetailsMode: Equatable, Hashable {
    case finishDetails
    case editGarment
    case cameraIntake
}

/// Sheet item so Edit vs Finish details mode is captured at present time (QA #267).
struct FinishDetailsPresentation: Identifiable, Hashable {
    let garmentId: UUID
    let mode: FinishDetailsMode

    var id: String {
        "\(garmentId.uuidString)-\(mode)"
    }

    static func edit(garmentId: UUID) -> FinishDetailsPresentation {
        FinishDetailsPresentation(garmentId: garmentId, mode: .editGarment)
    }

    static func finish(garmentId: UUID) -> FinishDetailsPresentation {
        FinishDetailsPresentation(garmentId: garmentId, mode: .finishDetails)
    }
}

enum FinishDetailsDismissDecision: Equatable {
    case dismiss
    case confirmDiscard
}

/// Editable field snapshot so Cancel / dismiss can compare against the seeded garment.
struct FinishDetailsSnapshot: Equatable {
    var slot: StubSlot
    var name: String
    var colorFamilyId: String
    var colorHex: String
    var colorDisplayName: String
    var pattern: String
    var surface: String
    var formality: Int?
    var warmth: Int?
    var priceText: String
    var currency: String
    var includePurchaseDate: Bool
    var purchaseDate: Date
    var priorWearBucket: String
}

enum FinishDetailsDraft {
    static func isDirty(seeded: FinishDetailsSnapshot, current: FinishDetailsSnapshot) -> Bool {
        seeded != current
    }

    static func dismissDecision(isDirty: Bool) -> FinishDetailsDismissDecision {
        isDirty ? .confirmDiscard : .dismiss
    }

    static func shouldConfirmDismiss(isDirty: Bool) -> Bool {
        dismissDecision(isDirty: isDirty) == .confirmDiscard
    }

    static func blocksInteractiveDismiss(isDirty: Bool, isSaving: Bool) -> Bool {
        isDirty || isSaving
    }

    /// Discard confirmation never calls the store — the seeded snapshot stays canonical.
    static func discardWritesToStore() -> Bool { false }

    static func snapshotAfterDiscard(seeded: FinishDetailsSnapshot) -> FinishDetailsSnapshot {
        seeded
    }

    static func showsSlotChangeFootnote(selected: StubSlot, saved: StubSlot) -> Bool {
        selected != saved
    }

    static func showsNextDraftQueue(mode: FinishDetailsMode) -> Bool {
        mode == .finishDetails
    }

    static func dismissesAfterSuccessfulSave(mode: FinishDetailsMode) -> Bool {
        mode == .editGarment || mode == .cameraIntake
    }

    static func placesNameAndCategoryFirst(mode: FinishDetailsMode) -> Bool {
        mode == .editGarment || mode == .cameraIntake
    }

    static func requiresExplicitSlot(mode: FinishDetailsMode) -> Bool {
        mode == .cameraIntake
    }
}
