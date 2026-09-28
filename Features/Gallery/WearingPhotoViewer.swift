import SwiftUI
import UIKit

/// Sprint 9 single wearing photo (#121): view, crop, remove, and retry Save to Photos.
struct WearingPhotoViewer: View {
    @ObservedObject var session: WearingGallerySession
    let photoId: UUID
    let garmentName: String

    @Environment(\.dismiss) private var dismiss
    @State private var cropPayload: CropEditorPayload?
    @State private var confirmRemove = false

    private var photo: StubWearingPhoto? { session.photos.first { $0.id == photoId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let photo {
                    VStack(alignment: .leading, spacing: 16) {
                        WearingPhotoThumbnail(files: session.files, photo: photo, height: 460, fitsWholePhoto: true)
                            .accessibilityLabel(WearingGalleryCopy.photoAccessibility(addedAt: photo.addedAt))
                        Text(garmentName)
                            .font(.headline)
                        Text(WearingGalleryCopy.addedOn(photo.addedAt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        exportStatus(photo)
                        HStack(spacing: 12) {
                            Button {
                                beginCrop(photo)
                            } label: {
                                Label(WearingGalleryCopy.crop, systemImage: "crop")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.isSaving)
                            .accessibilityIdentifier("wearing.viewer.crop")
                            Button(role: .destructive) {
                                confirmRemove = true
                            } label: {
                                Label(WearingGalleryCopy.remove, systemImage: "trash")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .disabled(session.isSaving)
                            .accessibilityIdentifier("wearing.viewer.remove")
                        }
                        if let message = session.message {
                            Text(message).font(.footnote)
                        }
                    }
                    .padding()
                } else {
                    ContentUnavailableView(WearingGalleryCopy.photoTitle, systemImage: "photo",
                                           description: Text(WearingGalleryCopy.saveFailure(.photoUnavailable)))
                }
            }
            .navigationTitle(WearingGalleryCopy.photoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(WearingGalleryCopy.done) { dismiss() }
                }
            }
            .confirmationDialog(WearingGalleryCopy.removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(WearingGalleryCopy.remove, role: .destructive) {
                    guard let photo else { return }
                    Task {
                        await session.remove(photo)
                        dismiss()
                    }
                }
                Button(WearingGalleryCopy.cancel, role: .cancel) {}
            } message: {
                Text(WearingGalleryCopy.removeMessage)
            }
            .fullScreenCover(item: $cropPayload) { payload in
                CropEditorView(
                    image: payload.image,
                    title: CropEditorCopy.wearingTitle,
                    aspects: [.original, .portrait4x5, .square],
                    isSaving: session.isSaving,
                    onCancel: { cropPayload = nil },
                    onSave: { result in
                        Task { await saveCrop(result, payload: payload) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func exportStatus(_ photo: StubWearingPhoto) -> some View {
        if photo.source == .camera {
            switch photo.exportState {
            case .saved:
                Label(WearingGalleryCopy.exportMessage(.saved), systemImage: "checkmark.circle")
                    .font(.footnote)
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    Label(WearingGalleryCopy.notSavedToPhotos, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                    Button(WearingGalleryCopy.retrySaveToPhotos) {
                        Task { await session.exportToPhotos(photo) }
                    }
                    .frame(minHeight: 44)
                    .disabled(session.exportingIds.contains(photo.id))
                    .accessibilityIdentifier("wearing.viewer.retryExport")
                    Button(WearingGalleryCopy.openSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .frame(minHeight: 44)
                }
            case nil:
                EmptyView()
            }
        }
    }

    private func beginCrop(_ photo: StubWearingPhoto) {
        guard let image = session.editSourceImage(for: photo) else {
            session.message = WearingGalleryCopy.loadFailed
            return
        }
        cropPayload = CropEditorPayload(image: image)
    }

    @MainActor
    private func saveCrop(_ result: CropEditResult, payload: CropEditorPayload) async {
        guard let photo else { cropPayload = nil; return }
        // Untouched, or the full source while the full source is already shown: no write.
        let showsFullSource = photo.sourceFileId == nil || photo.sourceFileId == photo.displayFileId
        if result.isUntouched || (result.isFullImage && showsFullSource) {
            cropPayload = nil
            return
        }
        let image = payload.image
        let rect = result.pixelRect
        let encoded = await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let cropped = PhotoEditing.cropped(image, to: rect) else { return nil }
            return PhotoEditing.jpegData(cropped, quality: 0.9)
        }.value
        guard let jpeg = encoded else {
            session.message = WearingGalleryCopy.saveFailure(.saveFailed)
            return
        }
        if await session.updateCrop(of: photo, displayJPEG: jpeg) {
            cropPayload = nil
        }
    }
}

/// View all: every wearing photo, newest first.
struct WearingGalleryGridView: View {
    @ObservedObject var session: WearingGallerySession
    let garmentName: String
    @State private var viewing: StubWearingPhoto?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(session.photos) { photo in
                    Button {
                        viewing = photo
                    } label: {
                        WearingPhotoThumbnail(files: session.files, photo: photo, height: 104)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(WearingGalleryCopy.photoAccessibility(addedAt: photo.addedAt))
                }
            }
            .padding()
        }
        .navigationTitle(WearingGalleryCopy.galleryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewing) { photo in
            WearingPhotoViewer(session: session, photoId: photo.id, garmentName: garmentName)
        }
    }
}
