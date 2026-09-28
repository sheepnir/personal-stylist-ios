import PhotosUI
import SwiftUI

struct ProfilePhotoSection: View {
    @State private var selection: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Sprint 9 (#120): a new pick or an existing picture opens the square crop editor.
    /// Nothing is written until Save; Cancel keeps the current picture.
    @State private var crop: CropEditorPayload?
    @State private var pendingNewSource: Data?
    @State private var isSavingCrop = false
    private let store = ProfilePhotoStore()

    var body: some View {
        Section {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .accessibilityLabel("Profile picture")
            }
            PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                Label(photo == nil ? "Add profile picture" : "Replace profile picture", systemImage: "photo")
                    .frame(minHeight: 44)
            }
            .disabled(isLoading || isSavingCrop)
            if photo != nil {
                Button {
                    beginEditingExisting()
                } label: {
                    Label(CropEditorCopy.editProfilePicture, systemImage: "crop")
                        .frame(minHeight: 44)
                }
                .disabled(isLoading || isSavingCrop)
                .accessibilityHint(CropEditorCopy.cropPhotoHint)
                Button("Remove profile picture", role: .destructive) {
                    do {
                        try store.remove()
                        photo = nil
                        selection = nil
                        errorMessage = nil
                    } catch {
                        errorMessage = "Couldn’t remove your picture. Please try again."
                    }
                }
                .frame(minHeight: 44)
                .disabled(isLoading || isSavingCrop)
            }
            if isLoading { ProgressView("Loading picture…") }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            }
        } header: {
            Text("Profile picture")
        } footer: {
            Text("Your picture stays on this iPhone. It isn’t sent to the outfit service or used for analysis.")
        }
        .onAppear {
            do { photo = try store.load().flatMap(UIImage.init(data:)) }
            catch { errorMessage = "Couldn’t load your picture. Please try again." }
        }
        .task(id: selection) {
            guard let item = selection else { return }
            isLoading = true
            defer { if selection == item { isLoading = false; selection = nil } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ProfilePhotoStore.StoreError.invalidImage
                }
                try Task.checkCancellation()
                guard let image = PhotoEditing.normalizedImage(from: data),
                      let source = PhotoEditing.jpegData(image, quality: 0.95) else {
                    throw ProfilePhotoStore.StoreError.invalidImage
                }
                pendingNewSource = source
                crop = CropEditorPayload(image: image)
                errorMessage = nil
            } catch is CancellationError {
                // Leaving the screen or cancelling a transfer keeps the old photo.
            } catch {
                errorMessage = "Couldn’t use that picture. Your existing picture is unchanged."
            }
        }
        .fullScreenCover(item: $crop) { payload in
            CropEditorView(
                image: payload.image,
                title: CropEditorCopy.profileTitle,
                aspects: [.square],
                isSaving: isSavingCrop,
                onCancel: {
                    crop = nil
                    pendingNewSource = nil
                },
                onSave: { result in
                    save(result, payload: payload)
                }
            )
        }
    }

    private func beginEditingExisting() {
        guard let data = try? store.loadEditSource(),
              let image = PhotoEditing.normalizedImage(from: data) else {
            errorMessage = CropEditorCopy.loadFailedMessage
            return
        }
        pendingNewSource = nil
        crop = CropEditorPayload(image: image)
    }

    @MainActor
    private func save(_ result: CropEditResult, payload: CropEditorPayload) {
        guard !isSavingCrop else { return }
        let newSource = pendingNewSource
        if result.isUntouched && newSource == nil {
            // Re-opening the current picture and saving unchanged rewrites nothing.
            crop = nil
            return
        }
        isSavingCrop = true
        let image = payload.image
        let rect = result.pixelRect
        let store = self.store
        Task {
            // Crop, encode and the durable write run off the main thread.
            let saved = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let cropped = PhotoEditing.cropped(image, to: rect),
                      let jpeg = PhotoEditing.jpegData(cropped, quality: 0.95) else { return nil }
                return try? store.replace(croppedDisplay: jpeg, newSource: newSource)
            }.value
            if let saved {
                photo = UIImage(data: saved)
                errorMessage = nil
            } else {
                errorMessage = "Couldn’t save that picture. Your existing picture is unchanged."
            }
            isSavingCrop = false
            crop = nil
            pendingNewSource = nil
        }
    }
}
