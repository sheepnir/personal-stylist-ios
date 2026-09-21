import Foundation

/// D-73 / #192 Take photo copy — local single-garment intake. Never raw enums, HTTP, or URLs.
enum CameraIntakeCopy {
    static let takePhoto = "Take photo"
    static let takePhotoSubtitle = "Photograph a garment. The photo stays on this iPhone."
    static let takePhotoHint = "Photograph a garment. The photo stays on this iPhone for your wardrobe."
    static let cameraUsageDescription =
        "To photograph a garment. The photo stays on this iPhone for your wardrobe."

    static let retake = "Retake"
    static let usePhoto = "Use photo"
    static let cancel = "Cancel"

    static let nameAndCategory = GarmentEditCopy.nameAndCategory
    static let slotLabel = GarmentEditCopy.slotLabel
    static let selectSlot = "Select…"
    static let untitledWithoutSlot = "Untitled"
    static let slotRequired = "Choose a slot before saving. Jeans belong in Bottom — don’t leave the category blank."
    static let cameraSheetFootnote =
        "This photo stays on this iPhone. Cancel discards it and adds no garment. Save keeps it in your wardrobe once a slot is chosen."

    static let openSettings = "Open Settings"
    static let deniedTitle = "Camera access is off"
    static let unavailableTitle = "Camera isn’t available"
    static let deniedMessage =
        "The photo is used for the garment locally. Open Settings to allow the camera, or add a piece from Photos or a sample instead."
    static let restrictedMessage =
        "Camera isn’t available for this app. Add a piece from Photos or use a sample instead."
    static let unavailableMessage =
        "Camera isn’t available on this device. Add a piece from Photos or use a sample instead."

    static let captureFailed =
        "Couldn’t keep that photo on this iPhone. Try again, or choose from Photos or a sample piece."
    static let lowStorage =
        "There isn’t enough storage to save this photo. Free up space and try again, or choose from Photos or a sample piece."
    static let interrupted =
        "The camera was interrupted. Try again when you’re ready, or choose from Photos or a sample piece."
    static let saveFailed = "Couldn’t save this garment. Try again."

    static func fallbackTitle(for state: CameraAuthorizationState) -> String {
        switch state {
        case .denied:
            return deniedTitle
        case .restricted, .unavailable:
            return unavailableTitle
        case .notDetermined, .authorized:
            return unavailableTitle
        }
    }

    static func fallbackMessage(for state: CameraAuthorizationState) -> String {
        switch state {
        case .denied:
            return deniedMessage
        case .restricted:
            return restrictedMessage
        case .unavailable, .notDetermined, .authorized:
            return unavailableMessage
        }
    }

    static func persistFailure(from error: Error) -> String {
        if let persist = error as? CameraPersistError {
            switch persist {
            case .lowStorage: return lowStorage
            case .slotRequired: return slotRequired
            case .pendingUnavailable, .saveFailed, .undecodableImage, .encodeFailed:
                return captureFailed
            }
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return lowStorage
        }
        return captureFailed
    }

    static var allUserFacingLines: [String] {
        [
            takePhoto, takePhotoSubtitle, takePhotoHint, cameraUsageDescription,
            retake, usePhoto, cancel, nameAndCategory, slotLabel, selectSlot,
            untitledWithoutSlot, slotRequired, cameraSheetFootnote, openSettings,
            deniedTitle, unavailableTitle, deniedMessage, restrictedMessage,
            unavailableMessage, captureFailed, lowStorage, interrupted, saveFailed,
        ]
    }
}
