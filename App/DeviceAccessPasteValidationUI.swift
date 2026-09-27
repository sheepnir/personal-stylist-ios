import Foundation

/// Paste-field UX for Profile device access (#34) — testable without SwiftUI.
enum DeviceAccessPasteValidationUI {
    /// Wrong-shape copy stays visible when the field is cleared programmatically after validation.
    /// Clear it only when the user enters new non-empty text.
    static func shouldClearWrongShapeMessage(whenPasteBufferChangesTo newValue: String) -> Bool {
        !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
