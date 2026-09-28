import Foundation
import UIKit

/// Sprint 9 wearing gallery for one garment (#121, #122, ADR-0004).
///
/// Local first: the gallery save commits before any Photos export, and an export failure
/// never removes the local photo. In-flight guards stop repeated taps from creating a second
/// association or a second export. Nothing here logs wear, changes counts or calls a model.
@MainActor
final class WearingGallerySession: ObservableObject {
    @Published private(set) var photos: [StubWearingPhoto] = []
    @Published private(set) var isSaving = false
    @Published private(set) var exportingIds: Set<UUID> = []
    /// Latest export outcome per photo in this session, so recovery (Settings) is offered
    /// only when it can help. Persisted state is `StubWearingPhoto.exportState`.
    @Published private(set) var exportOutcomes: [UUID: PhotoLibraryExportOutcome] = [:]
    /// Section-level status line. Cleared whenever a flow or viewer opens so an outcome
    /// about one photo is never shown next to another.
    @Published var message: String?

    let garmentId: UUID
    private let store: PersistenceStore
    private let exporter: PhotoLibraryExporting

    init(garmentId: UUID, store: PersistenceStore, exporter: PhotoLibraryExporting = SystemPhotoLibraryExporter()) {
        self.garmentId = garmentId
        self.store = store
        self.exporter = exporter
    }

    var files: WearingPhotoFileStore { store.wearingPhotoFiles }
    var latest: StubWearingPhoto? { photos.first }
    /// Up to five previews after the featured latest photo.
    var recentPreviews: [StubWearingPhoto] { Array(photos.dropFirst().prefix(WearingPhotoOrdering.recentLimit)) }

    func load() async {
        photos = await store.fetchWearingPhotos(garmentId: garmentId)
    }

    /// Commit one photo. `request.id` is fixed per add flow, so a retry cannot duplicate it.
    /// Returns nil (with `message` set) on failure; the gallery is then unchanged.
    @discardableResult
    func add(_ request: WearingPhotoAddRequest) async -> StubWearingPhoto? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let photo = try await store.addWearingPhoto(request)
            await load()
            return photo
        } catch {
            message = WearingGalleryCopy.saveFailure(WearingPhotoPersistError.map(error))
            return nil
        }
    }

    /// Save a copy of `photo`'s displayed picture to Photos. Records the outcome; never
    /// reports success on failure and never adds a gallery item.
    @discardableResult
    func exportToPhotos(_ photo: StubWearingPhoto) async -> PhotoLibraryExportOutcome? {
        guard photo.source == .camera, !exportingIds.contains(photo.id) else { return nil }
        guard let data = files.data(for: photo.displayFileId) else {
            _ = try? await store.setWearingPhotoExportState(id: photo.id, state: .failed)
            exportOutcomes[photo.id] = .failed
            await load()
            message = WearingGalleryCopy.exportMessage(.failed)
            return .failed
        }
        exportingIds.insert(photo.id)
        defer { exportingIds.remove(photo.id) }
        let outcome = await exporter.saveToPhotos(data)
        exportOutcomes[photo.id] = outcome
        let state: WearingPhotoExportState = outcome == .saved ? .saved : .failed
        _ = try? await store.setWearingPhotoExportState(id: photo.id, state: state)
        await load()
        message = WearingGalleryCopy.exportMessage(outcome)
        return outcome
    }

    /// Replace the displayed picture (crop). Order and the retained source are kept.
    @discardableResult
    func updateCrop(of photo: StubWearingPhoto, displayJPEG: Data) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.updateWearingPhotoDisplay(id: photo.id, displayJPEG: displayJPEG)
            await load()
            return true
        } catch {
            message = WearingGalleryCopy.saveFailure(WearingPhotoPersistError.map(error))
            return false
        }
    }

    /// Remove after the user confirmed. The garment, its reference photo, wear history and
    /// any copy already in Photos are untouched.
    func remove(_ photo: StubWearingPhoto) async {
        do {
            try await store.removeWearingPhoto(id: photo.id)
            message = WearingGalleryCopy.removed
        } catch {
            message = WearingGalleryCopy.removeFailed
        }
        await load()
    }

    /// Normalized source pixels for re-cropping (the retained source, else the display file).
    func editSourceImage(for photo: StubWearingPhoto) -> CGImage? {
        guard let data = files.data(for: photo.editSourceFileId) ?? files.data(for: photo.displayFileId) else {
            return nil
        }
        return PhotoEditing.normalizedImage(from: data)
    }
}

// MARK: - Thumbnails

extension WearingPhotoFileStore {
    private static let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Downsampled display bitmap. File ids change on every edit, so the cache never serves
    /// a stale crop.
    func thumbnail(for id: UUID, maxPixel: Int) -> UIImage? {
        let pixel = max(64, maxPixel)
        let key = "\(directory.path)/\(id.uuidString)#\(pixel)" as NSString
        if let cached = Self.thumbnailCache.object(forKey: key) { return cached }
        guard let data = data(for: id),
              let image = PhotoEditing.normalizedImage(from: data, maxPixel: pixel) else { return nil }
        let ui = UIImage(cgImage: image)
        Self.thumbnailCache.setObject(ui, forKey: key, cost: image.bytesPerRow * image.height)
        return ui
    }
}
