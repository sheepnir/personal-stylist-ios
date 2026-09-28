import Foundation

/// Sprint 9 crop editor and photo-edit copy (#120). No machine tokens or file paths.
enum CropEditorCopy {
    static let cancel = "Cancel"
    static let save = "Save"
    static let saving = "Saving photo"
    static let reset = "Reset"
    static let zoom = "Zoom"
    static let shape = "Crop shape"
    static let canvasLabel = "Crop area"
    static let canvasHint = "Drag to position the photo. Pinch, or swipe up or down, to zoom."

    static let profileTitle = "Crop profile picture"
    static let garmentTitle = "Crop photo"
    static let wearingTitle = "Crop photo"

    static let cropPhoto = "Crop photo"
    static let cropPhotoHint = "Adjust the framing. Your current photo stays until you save."
    static let editProfilePicture = "Crop profile picture"

    static let saveFailedTitle = "Couldn’t save the crop"
    static let saveFailedMessage = "Your previous photo is unchanged. Please try again."
    static let lowStorageMessage = "Your iPhone is low on storage. Your previous photo is unchanged."
    static let loadFailedMessage = "Couldn’t open that photo for editing. Your photo is unchanged."

    static func zoomValue(_ zoom: CGFloat) -> String {
        String(format: "%.1f times", Double(zoom))
    }

    static func label(for aspect: CropGeometry.Aspect) -> String {
        switch aspect {
        case .original: return "Original"
        case .portrait4x5: return "4:5"
        case .square: return "Square"
        }
    }
}
