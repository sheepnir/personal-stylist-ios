import Foundation
import Photos

/// Outcome of saving a copy to the system Photos library (#122). Separate from the local
/// gallery save, which always happens first and is never undone by an export failure.
enum PhotoLibraryExportOutcome: Equatable, Sendable {
    case saved
    case denied
    case restricted
    case failed
}

/// Seam for the system Photos library. Tests inject a fake; nothing here reads the library.
protocol PhotoLibraryExporting: Sendable {
    /// Requests add-only access when needed, then saves `jpeg` as a new photo.
    func saveToPhotos(_ jpeg: Data) async -> PhotoLibraryExportOutcome
}

/// Live exporter: add-only authorization (never read access), requested only when the user
/// has committed to saving a copy. The copy is independent of the app's local file.
struct SystemPhotoLibraryExporter: PhotoLibraryExporting {
    func saveToPhotos(_ jpeg: Data) async -> PhotoLibraryExportOutcome {
        let status = await Self.addOnlyAuthorization()
        switch status {
        case .authorized, .limited:
            break
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .denied
        @unknown default:
            return .failed
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpeg, options: nil)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    private static func addOnlyAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}
