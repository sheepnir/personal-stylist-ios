import Foundation

/// Sprint 9 "You wearing this" gallery and selfie copy (#121, #122). No machine tokens.
enum WearingGalleryCopy {
    static let sectionTitle = "You wearing this"
    static let sectionFootnote = "Your photos stay on this iPhone unless you choose Save to Photos. Adding a photo doesn’t log a wear."
    static let referenceLabel = "Reference photo"
    static let empty = "No photos of you wearing this yet."
    static let addPhoto = "Add wearing photo"
    static let addPhotoHint = "Take a selfie or choose a photo of you wearing this piece."
    static let takeSelfie = "Take selfie"
    static let chooseFromPhotos = "Choose from Photos"
    static let cancel = "Cancel"
    static let viewAll = "View all"
    static func viewAllAccessibility(_ count: Int) -> String { "View all \(count) photos of you wearing this" }
    static let latestLabel = "Latest photo of you wearing this"
    static func photoAccessibility(addedAt: Date, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.locale = locale
        return "Photo of you wearing this, added \(addedAt.formatted(style))"
    }
    static func addedOn(_ date: Date, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = locale
        return "Added \(date.formatted(style))"
    }
    static let galleryTitle = "You wearing this"
    static let photoTitle = "Photo"
    static let done = "Done"

    // Capture / confirm
    static let confirmTitle = "Add wearing photo"
    static func addingTo(_ garmentName: String) -> String { "Adding to \(garmentName)" }
    static let retake = "Retake"
    static let crop = "Crop"
    static let save = "Save"
    static let saving = "Saving photo"
    static let saveToPhotos = "Save to Photos"
    static let saveToPhotosFootnote = "Saves a separate copy to your Photos library, which may sync with your iCloud settings. Later edits here don’t change that copy."

    // Outcomes
    static let saved = "Photo added"
    static let savedToPhotos = "Photo added and saved to Photos"
    static let exportDenied = "Photo added here. Photos access is off, so it wasn’t saved to Photos."
    static let exportRestricted = "Photo added here. Saving to Photos isn’t allowed on this iPhone."
    static let exportFailed = "Photo added here, but it couldn’t be saved to Photos."
    static let retrySaveToPhotos = "Try Save to Photos again"
    static let openSettings = "Open Settings"
    static let notSavedToPhotos = "Not saved to Photos"
    static let removed = "Photo removed"
    static let removeFailed = "Couldn’t remove that photo. Please try again."

    static func exportMessage(_ outcome: PhotoLibraryExportOutcome) -> String {
        switch outcome {
        case .saved: return "Saved to Photos"
        case .denied: return exportDenied
        case .restricted: return exportRestricted
        case .failed: return exportFailed
        }
    }

    static func saveFailure(_ error: WearingPhotoPersistError) -> String {
        switch error {
        case .garmentUnavailable: return "This piece is no longer in your wardrobe, so the photo wasn’t added."
        case .photoUnavailable: return "That photo is no longer available."
        case .lowStorage: return "Your iPhone is low on storage. Nothing was changed."
        case .saveFailed: return "Couldn’t save that photo. Nothing was changed; please try again."
        }
    }

    // Removal
    static let remove = "Remove photo"
    static let removeTitle = "Remove this photo?"
    static let removeMessage = "It’s removed from this app only. The piece, its reference photo, your wear history and any copy in Photos stay."

    // Camera fallback
    static let cameraUnavailableTitle = "Camera not available"
    static let cameraDeniedMessage = "Camera access is off for Personal Stylist. You can turn it on in Settings, or choose a photo from your library instead."
    static let cameraRestrictedMessage = "The camera is restricted on this iPhone. You can choose a photo from your library instead."
    static let cameraUnavailableMessage = "This device has no available camera. You can choose a photo from your library instead."
    static let loadFailed = "Couldn’t open that photo. Nothing was changed."
}
