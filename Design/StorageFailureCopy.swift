import Foundation

/// Shown when the on-device wardrobe cannot be opened or a one-time reset did not finish.
/// No raw errors, and no path that saves into a temporary copy.
enum StorageFailureCopy {
    static let title = "Wardrobe unavailable"

    static let cleanStartIncomplete =
        "A one-time reset of this wardrobe did not finish. Nothing new can be saved. Quit the app and open it again so the reset can finish."

    static let wardrobeUnopened =
        "The wardrobe on this iPhone could not be opened. Your clothes were not copied into a temporary wardrobe, and nothing new can be saved. Quit the app and open it again."
}
