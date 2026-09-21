import Foundation

/// D-74 / #278 Change photo copy. Never raw enums, HTTP, or URLs.
enum PhotoReplaceCopy {
    static let changePhoto = "Change photo"
    static let changePhotoHint = "Replace this garment’s photo. The photo stays on this iPhone."
    static let changePhotoBusy = "Saving this photo. Wait until it finishes."
    static let chooseFromPhotos = "Choose from Photos"
    static let chooseFromPhotosHint = "Pick a replacement photo from your library. It stays on this iPhone."
    static let takePhoto = CameraIntakeCopy.takePhoto
    static let takePhotoHint = CameraIntakeCopy.takePhotoHint
    static let save = "Save"
    static let saveHint = "Keep this photo on the garment. The original is replaced only after Save."
    static let cancel = CameraIntakeCopy.cancel
    static let chooseAnother = "Choose another"
    static let chooseAnotherHint = "Discard this preview and pick a different photo."
    static let previewTitle = "New photo"
    static let previewNavCancelHint = "Closes this preview and keeps the original photo."
    static let previewFooterCancelHint =
        "Keeps the original photo. This preview is discarded."
    static let saved = "Photo updated"
    static let staysOnDevice =
        "This photo stays on this iPhone. Cancel keeps the original."

    static let openSettings = CameraIntakeCopy.openSettings
    static let deniedTitle = CameraIntakeCopy.deniedTitle
    static let unavailableTitle = CameraIntakeCopy.unavailableTitle
    static let deniedMessage =
        "The photo is used for the garment locally. Open Settings to allow the camera, or choose from Photos instead."
    static let restrictedMessage =
        "Camera isn’t available for this app. Choose from Photos instead."
    static let unavailableMessage =
        "Camera isn’t available on this device. Choose from Photos instead."

    static let captureFailed =
        "Couldn’t keep that photo on this iPhone. Try again, or choose from Photos."
    static let decodeFailed =
        "That item wasn’t a usable photo. Try another, or take a new photo."
    static let lowStorage =
        "There isn’t enough storage to save this photo. Free up space and try again."
    static let saveFailed = "Couldn’t update this photo. The original is unchanged."

    static func fallbackTitle(for state: CameraAuthorizationState) -> String {
        switch state {
        case .denied:
            return deniedTitle
        case .restricted, .unavailable, .notDetermined, .authorized:
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
        if let persist = error as? PhotoReplacePersistError {
            switch persist {
            case .lowStorage: return lowStorage
            case .undecodableImage: return decodeFailed
            case .garmentUnavailable, .saveFailed, .encodeFailed:
                return saveFailed
            }
        }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return lowStorage
        }
        return captureFailed
    }

    static func changePhotoAccessibilityHint(commitInFlight: Bool) -> String {
        commitInFlight ? changePhotoBusy : changePhotoHint
    }

    /// Spoken failure string for VoiceOver. Never `Error.description`.
    static func failureAnnouncement(from error: Error) -> String {
        persistFailure(from: error)
    }

    static func containsMachineToken(_ text: String) -> Bool {
        let forbidden = [
            "HTTP", "http://", "https://", "NSURL", "token",
            "attributeSource", "PendingCapture", "GarmentEntity",
            "replaceGarmentPhoto", "NSPhotoLibrary", "PHPhotoLibrary",
            "Error.description", "NSError",
        ]
        return forbidden.contains { text.contains($0) }
    }

    static var allUserFacingLines: [String] {
        [
            changePhoto, changePhotoHint, changePhotoBusy, chooseFromPhotos, chooseFromPhotosHint,
            takePhoto, takePhotoHint, save, saveHint, cancel, chooseAnother, chooseAnotherHint,
            previewTitle, previewNavCancelHint, previewFooterCancelHint, saved, staysOnDevice,
            openSettings, deniedTitle, unavailableTitle, deniedMessage, restrictedMessage,
            unavailableMessage, captureFailed, decodeFailed, lowStorage, saveFailed,
        ]
    }
}
