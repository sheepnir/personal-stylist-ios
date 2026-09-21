import Foundation

/// User-facing copy for destructive data controls (D-69 / D-70 / D-71).
/// Names exact scope. Never “Delete everything”, machine tokens, or HTTP/URL errors.
enum DataControlsCopy {
    static let cancel = "Cancel"

    // MARK: - Delete garment (D-69)

    static let deleteGarmentAction = "Delete garment"
    static let deleteGarmentTitle = "Delete this garment?"
    static let deleteGarmentSuccess = "Garment deleted"
    static let deleteGarmentFailure = "Couldn’t delete that garment. Try again."

    static func deleteGarmentMessage(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "this garment" : trimmed
        return "This permanently removes \(label) and its photos. Looks that used it will be deleted. Wear history for this piece is removed. Your other garments and style profile stay. This cannot be undone."
    }

    // MARK: - Reset profile (D-71)

    static let resetProfileAction = "Reset profile"
    static let resetProfileTitle = "Reset style profile?"
    static let resetProfileSuccess = "Profile reset"
    static let resetProfileFailure = "Couldn’t reset your profile. Try again."
    static let resetProfileMessage =
        "This clears your current answers, summary, and confirmation so you can set up your profile again. Wardrobe, looks, and wear history stay. Older looks keep the profile they were created with. Device access stays. This cannot be undone."

    // MARK: - Clear wardrobe and looks (D-70)

    static let clearWardrobeAction = "Clear wardrobe and looks"
    static let clearWardrobeTitle = "Clear wardrobe and looks?"
    static let clearWardrobeSuccess = "Wardrobe and looks cleared"
    static let clearWardrobeFailure = "Couldn’t clear wardrobe and looks. Try again."
    static let clearWardrobeMessage =
        "This permanently removes all garments, photos, saved looks, and their wear history. Your style profile and device access stay. This cannot be undone."
}
