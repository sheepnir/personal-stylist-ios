import AVFoundation
import UIKit

/// Testable camera permission snapshot (D-73). No UI and no authorization prompt.
enum CameraAuthorizationStatus: String, Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case unavailable
    case notDetermined
}

enum CameraAuthorization {
    struct Probe: Sendable {
        var authorizationStatus: @Sendable (AVMediaType) -> AVAuthorizationStatus
        var cameraAvailable: @Sendable () -> Bool

        static let live = Probe(
            authorizationStatus: { AVCaptureDevice.authorizationStatus(for: $0) },
            cameraAvailable: { UIImagePickerController.isSourceTypeAvailable(.camera) }
        )
    }

    static func status(using probe: Probe = .live) -> CameraAuthorizationStatus {
        guard probe.cameraAvailable() else { return .unavailable }
        switch probe.authorizationStatus(.video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unavailable
        }
    }
}
