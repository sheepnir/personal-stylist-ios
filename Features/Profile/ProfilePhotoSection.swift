import PhotosUI
import SwiftUI

struct ProfilePhotoSection: View {
    @State private var selection: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
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
            .disabled(isLoading)
            if photo != nil {
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
                .disabled(isLoading)
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
                let saved = try store.replace(with: data)
                photo = UIImage(data: saved)
                errorMessage = nil
            } catch is CancellationError {
                // Leaving the screen or cancelling a transfer keeps the old photo.
            } catch {
                errorMessage = "Couldn’t save that picture. Your existing picture is unchanged."
            }
        }
    }
}
