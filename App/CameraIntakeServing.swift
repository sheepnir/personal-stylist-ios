import AVFoundation
import Foundation
import UIKit

/// Preview handle after `PersistenceStore.beginCameraPending`. Not a garment.
struct CameraPending: Equatable, Identifiable, Sendable {
    let id: UUID
    let imagePath: String

    /// Preview-only DTO. `slot` is a non-null StubGarment requirement — callers must
    /// not treat a placeholder as a chosen category (`CameraIntakeDraft.isSlotChosen`).
    func previewGarment(displayName: String, slot: StubSlot?) -> StubGarment {
        StubGarment(
            id: id,
            displayName: displayName,
            slot: slot ?? .accessory,
            readiness: .draft,
            availability: "AVAILABLE",
            colorPrimary: nil,
            pattern: nil,
            surface: nil,
            imagePath: imagePath,
            formality: nil,
            warmth: nil,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(),
            displayNameSource: "DERIVED"
        )
    }
}

struct CameraIntakeCommitFields: Equatable, Sendable {
    var slot: StubSlot
    var displayName: String
    var displayNameIsUserSet: Bool
    var color: StubColorPrimary
    var pattern: String
    var surface: String
    var formality: Int?
    var warmth: Int?
    var purchasePrice: Decimal?
    var purchaseCurrency: String?
    var purchaseDate: Date?
    var priorWearBucket: String?
    var markReady: Bool
}

enum CameraAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

enum CameraPermissionAction: Equatable {
    case requestAccess
    case presentCamera
    case offerSettingsOrFallback
}

enum CameraPermissionPolicy {
    static func resolvedState(
        authorization: CameraAuthorizationStatus,
        cameraAvailable: Bool
    ) -> CameraAuthorizationState {
        if authorization == .unavailable || !cameraAvailable { return .unavailable }
        switch authorization {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .unavailable: return .unavailable
        }
    }

    static func action(for state: CameraAuthorizationState) -> CameraPermissionAction {
        switch state {
        case .notDetermined:
            return .requestAccess
        case .authorized:
            return .presentCamera
        case .denied, .restricted, .unavailable:
            return .offerSettingsOrFallback
        }
    }

    static func showsOpenSettings(for state: CameraAuthorizationState) -> Bool {
        state == .denied || state == .restricted
    }

    static func currentAuthorization() -> CameraAuthorizationStatus {
        CameraAuthorization.status()
    }

    static func isCameraAvailable() -> Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

enum CameraIntakeDraft {
    static func defaultSlotForCameraIntake() -> StubSlot? { nil }

    static func isSlotChosen(_ slot: StubSlot?) -> Bool { slot != nil }

    static func canPersist(slot: StubSlot?) -> Bool { slot != nil }

    static func abandonWritesGarment() -> Bool { false }

    static func retakeWritesGarment() -> Bool { false }

    static func previewCancelWritesGarment() -> Bool { false }

    static func liveDisplayName(name: String, slot: StubSlot?) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let slot { return StubGarment.untitledName(for: slot) }
        return CameraIntakeCopy.untitledWithoutSlot
    }
}
