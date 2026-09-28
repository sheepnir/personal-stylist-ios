import SwiftUI
import UIKit

/// Sprint 9 selfie / import confirm flow (#122). Nothing is written until Save; Retake and
/// Cancel leave no file and no export. The local gallery save commits first; the optional
/// Photos copy is the exact confirmed (and cropped) picture, exported afterwards.
struct WearingPhotoCaptureFlow: View {
    let item: WearingCaptureFlowItem
    let garmentName: String
    @ObservedObject var session: WearingGallerySession
    var onFinish: () -> Void

    @State private var captured: CGImage?
    @State private var cropRect: CGRect?
    @State private var cropPayload: CropEditorPayload?
    @State private var saveToPhotos = true
    /// One id per confirmed picture: a retried Save cannot add a second gallery item.
    @State private var requestId = UUID()
    @State private var isFinishing = false

    init(item: WearingCaptureFlowItem, garmentName: String, session: WearingGallerySession, onFinish: @escaping () -> Void) {
        self.item = item
        self.garmentName = garmentName
        self.session = session
        self.onFinish = onFinish
        _captured = State(initialValue: item.image)
    }

    var body: some View {
        if let captured {
            confirm(captured)
        } else {
            SystemCameraPicker(
                onImage: { image in
                    if let normalized = PhotoEditing.normalizedImage(from: image) {
                        cropRect = nil
                        requestId = UUID()
                        captured = normalized
                    } else {
                        session.message = WearingGalleryCopy.loadFailed
                        onFinish()
                    }
                },
                onCancel: onFinish,
                prefersFrontCamera: true
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("wearing.camera")
        }
    }

    private func displayed(_ image: CGImage) -> CGImage {
        guard let cropRect, let cropped = PhotoEditing.cropped(image, to: cropRect) else { return image }
        return cropped
    }

    private func confirm(_ image: CGImage) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(uiImage: UIImage(cgImage: displayed(image)))
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(WearingGalleryCopy.photoTitle)
                    Label(WearingGalleryCopy.addingTo(garmentName), systemImage: "tshirt")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 12) {
                        Button {
                            cropPayload = CropEditorPayload(image: image)
                        } label: {
                            Label(WearingGalleryCopy.crop, systemImage: "crop")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("wearing.confirm.crop")
                        if item.source == .camera {
                            Button {
                                retake()
                            } label: {
                                Label(WearingGalleryCopy.retake, systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("wearing.confirm.retake")
                        }
                    }
                    .disabled(isFinishing)
                    if item.source == .camera {
                        Toggle(WearingGalleryCopy.saveToPhotos, isOn: $saveToPhotos)
                            .frame(minHeight: 44)
                            .disabled(isFinishing)
                            .accessibilityIdentifier("wearing.confirm.saveToPhotos")
                        Text(WearingGalleryCopy.saveToPhotosFootnote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let message = session.message, isFinishing == false {
                        Text(message)
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle(WearingGalleryCopy.confirmTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(WearingGalleryCopy.cancel, action: onFinish)
                        .disabled(isFinishing)
                        .accessibilityIdentifier("wearing.confirm.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isFinishing {
                        ProgressView().accessibilityLabel(WearingGalleryCopy.saving)
                    } else {
                        Button(WearingGalleryCopy.save) {
                            Task { await save(image) }
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("wearing.confirm.save")
                    }
                }
            }
            .fullScreenCover(item: $cropPayload) { payload in
                CropEditorView(
                    image: payload.image,
                    title: CropEditorCopy.wearingTitle,
                    aspects: [.original, .portrait4x5, .square],
                    onCancel: { cropPayload = nil },
                    onSave: { result in
                        // Untouched keeps the crop already chosen; full image clears it.
                        if !result.isUntouched {
                            cropRect = result.isFullImage ? nil : result.pixelRect
                        }
                        cropPayload = nil
                    }
                )
            }
        }
        .interactiveDismissDisabled(isFinishing)
    }

    private func retake() {
        cropRect = nil
        requestId = UUID()
        captured = nil
    }

    @MainActor
    private func save(_ image: CGImage) async {
        guard !isFinishing else { return }
        isFinishing = true
        session.message = nil
        let shown = displayed(image)
        // Two JPEG encodes of up to 1600 px run off the main thread.
        let encoded = await Task.detached(priority: .userInitiated) { () -> (Data, Data)? in
            guard let display = PhotoEditing.jpegData(shown, quality: 0.9),
                  let source = PhotoEditing.jpegData(image, quality: 0.95) else { return nil }
            return (display, source)
        }.value
        guard let encoded else {
            session.message = WearingGalleryCopy.saveFailure(.saveFailed)
            isFinishing = false
            return
        }
        let (displayJPEG, sourceJPEG) = encoded
        let request = WearingPhotoAddRequest(
            id: requestId,
            garmentId: session.garmentId,
            displayJPEG: displayJPEG,
            sourceJPEG: sourceJPEG,
            source: item.source
        )
        guard let photo = await session.add(request) else {
            // Stay here so Save can be retried; the same id keeps it a single photo.
            isFinishing = false
            return
        }
        if item.source == .camera && saveToPhotos {
            await session.exportToPhotos(photo)
        } else {
            session.message = WearingGalleryCopy.saved
        }
        onFinish()
    }
}
