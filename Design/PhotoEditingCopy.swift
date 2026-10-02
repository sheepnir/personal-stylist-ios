import Foundation

/// Sprint 9 crop editor and photo-edit copy (#120). No machine tokens or file paths.
enum CropEditorCopy {
    static let cancel = "Cancel"
    static let save = "Save"
    static let saving = "Saving photo"
    static let reset = "Reset"
    static let zoom = "Zoom"
    static let horizontalPosition = "Move photo horizontally"
    static let verticalPosition = "Move photo vertically"
    static let positionHint = "Swipe up or down to move the photo within the crop area."
    static let positionUnavailable = "Zoom in to move the photo on this axis."
    static let shape = "Crop shape"
    static let canvasLabel = "Crop area"
    static let canvasHint = "Swipe up or down to zoom. Use the position sliders to move the photo."

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

    static func positionValue(_ value: CGFloat, horizontal: Bool) -> String {
        if abs(value) < 0.01 { return "Centred" }
        let direction = horizontal ? (value < 0 ? "left" : "right") : (value < 0 ? "up" : "down")
        return "\(Int((abs(value) * 100).rounded())) percent \(direction)"
    }

    static func label(for aspect: CropGeometry.Aspect) -> String {
        switch aspect {
        case .original: return "Original"
        case .portrait4x5: return "4:5"
        case .square: return "Square"
        }
    }
}
