import PhotosUI
import SwiftUI
import UIKit

/// Sprint 9 "You wearing this" section on garment detail (#121, #122, ADR-0004).
/// Separate from the reference photo. Latest photo featured, up to five recent previews,
/// View all for the rest. Adding a photo never logs a wear or changes counts.
struct WearingGallerySection: View {
    let garment: StubGarment
    @StateObject private var session: WearingGallerySession

    @State private var showSourceChoice = false
    @State private var showLibraryPicker = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isLoadingLibrary = false
    @State private var flow: WearingCaptureFlowItem?
    @State private var cameraFallback: CameraAuthorizationState?
    @State private var viewing: StubWearingPhoto?

    init(garment: StubGarment, store: PersistenceStore, exporter: PhotoLibraryExporting = SystemPhotoLibraryExporter()) {
        self.garment = garment
        _session = StateObject(wrappedValue: WearingGallerySession(garmentId: garment.id, store: store, exporter: exporter))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(WearingGalleryCopy.sectionTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let latest = session.latest {
                Button {
                    viewing = latest
                } label: {
                    WearingPhotoThumbnail(files: session.files, photo: latest, height: 260)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WearingGalleryCopy.latestLabel)
                .accessibilityHint(WearingGalleryCopy.photoAccessibility(addedAt: latest.addedAt))
                .accessibilityIdentifier("wearing.latest")
                if !session.recentPreviews.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(session.recentPreviews) { photo in
                                Button {
                                    viewing = photo
                                } label: {
                                    WearingPhotoThumbnail(files: session.files, photo: photo, height: 72, width: 72)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(WearingGalleryCopy.photoAccessibility(addedAt: photo.addedAt))
                            }
                        }
                    }
                }
                if session.photos.count > 1 {
                    NavigationLink {
                        WearingGalleryGridView(session: session, garmentName: garment.displayName)
                    } label: {
                        Text("\(WearingGalleryCopy.viewAll) (\(session.photos.count))")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel(WearingGalleryCopy.viewAllAccessibility(session.photos.count))
                    .accessibilityIdentifier("wearing.viewAll")
                }
            } else {
                Text(WearingGalleryCopy.empty)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            Button {
                showSourceChoice = true
            } label: {
                Label(WearingGalleryCopy.addPhoto, systemImage: "person.crop.square.badge.camera")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(session.isSaving || isLoadingLibrary)
            .accessibilityHint(WearingGalleryCopy.addPhotoHint)
            .accessibilityIdentifier("wearing.add")
            if isLoadingLibrary {
                ProgressView()
            }
            if let message = session.message {
                Text(message)
                    .font(.footnote)
                    .accessibilityIdentifier("wearing.message")
            }
            Text(WearingGalleryCopy.sectionFootnote)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .task { await session.load() }
        .confirmationDialog(WearingGalleryCopy.addPhoto, isPresented: $showSourceChoice, titleVisibility: .visible) {
            Button(WearingGalleryCopy.takeSelfie) { takeSelfie() }
            Button(WearingGalleryCopy.chooseFromPhotos) { showLibraryPicker = true }
            Button(WearingGalleryCopy.cancel, role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $libraryItem, matching: .images, photoLibrary: .shared())
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task { await loadLibraryItem(item) }
        }
        .fullScreenCover(item: $flow) { item in
            WearingPhotoCaptureFlow(item: item, garmentName: garment.displayName, session: session) {
                flow = nil
            }
        }
        .sheet(item: $viewing) { photo in
            WearingPhotoViewer(session: session, photoId: photo.id, garmentName: garment.displayName)
        }
        .alert(
            WearingGalleryCopy.cameraUnavailableTitle,
            isPresented: Binding(get: { cameraFallback != nil }, set: { if !$0 { cameraFallback = nil } })
        ) {
            if let state = cameraFallback, CameraPermissionPolicy.showsOpenSettings(for: state) {
                Button(WearingGalleryCopy.openSettings) { openSettings() }
            }
            Button(WearingGalleryCopy.chooseFromPhotos) { showLibraryPicker = true }
            Button(WearingGalleryCopy.cancel, role: .cancel) {}
        } message: {
            Text(fallbackMessage(cameraFallback))
        }
    }

    private func takeSelfie() {
        let state = CameraPermissionPolicy.resolvedState(
            authorization: CameraPermissionPolicy.currentAuthorization(),
            cameraAvailable: CameraPermissionPolicy.isCameraAvailable()
        )
        switch CameraPermissionPolicy.action(for: state) {
        case .requestAccess:
            Task {
                let granted = await CameraPermissionPolicy.requestAccess()
                if granted && CameraPermissionPolicy.isCameraAvailable() {
                    flow = WearingCaptureFlowItem(source: .camera, image: nil)
                } else {
                    cameraFallback = granted ? .unavailable : .denied
                }
            }
        case .presentCamera:
            flow = WearingCaptureFlowItem(source: .camera, image: nil)
        case .offerSettingsOrFallback:
            cameraFallback = state
        }
    }

    @MainActor
    private func loadLibraryItem(_ item: PhotosPickerItem) async {
        isLoadingLibrary = true
        defer {
            isLoadingLibrary = false
            libraryItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = PhotoEditing.normalizedImage(from: data) else {
            session.message = WearingGalleryCopy.loadFailed
            return
        }
        flow = WearingCaptureFlowItem(source: .library, image: image)
    }

    private func fallbackMessage(_ state: CameraAuthorizationState?) -> String {
        switch state {
        case .denied: return WearingGalleryCopy.cameraDeniedMessage
        case .restricted: return WearingGalleryCopy.cameraRestrictedMessage
        default: return WearingGalleryCopy.cameraUnavailableMessage
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// One capture or import flow. The camera starts without an image.
struct WearingCaptureFlowItem: Identifiable {
    let id = UUID()
    let source: WearingPhotoSource
    let image: CGImage?
}

/// Downsampled gallery image, decoded off the main thread. Clipped drawing and hit area
/// match (Sprint 8 lesson: a scaled photo must not cover nearby controls).
struct WearingPhotoThumbnail: View {
    let files: WearingPhotoFileStore
    let photo: StubWearingPhoto
    var height: CGFloat
    var width: CGFloat? = nil
    /// Viewer shows the whole picture; grids and previews fill their cell.
    var fitsWholePhoto: Bool = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fitsWholePhoto ? .fit : .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: width ?? .infinity)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task(id: photo.displayFileId) {
            let pixel = Int(max(height, width ?? height) * displayScale * 1.5)
            let files = self.files
            let id = photo.displayFileId
            image = await Task.detached(priority: .userInitiated) {
                files.thumbnail(for: id, maxPixel: pixel)
            }.value
        }
    }
}
