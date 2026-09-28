import SwiftUI
import UIKit

/// Sprint 9 shared crop editor (#120) for profile, garment reference and wearing photos.
/// Drag to position, pinch or use the slider to zoom. Save returns a pixel rect only; the
/// presenting screen owns encoding and persistence. Cancel changes nothing.
struct CropEditorView: View {
    let image: CGImage
    let title: String
    let aspects: [CropGeometry.Aspect]
    var isSaving: Bool = false
    var onCancel: () -> Void
    var onSave: (CropEditResult) -> Void

    @State private var aspect: CropGeometry.Aspect
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    /// Live gesture values reset automatically if the system cancels a gesture, so the
    /// preview can never differ from what Save commits.
    @GestureState private var gestureZoom: CGFloat = 1
    @GestureState private var gestureTranslation: CGSize = .zero
    /// Frame size of the last layout; Save converts with the frame the user saw.
    @State private var lastFrame: CGSize = .zero
    /// Untouched editors save nothing (callers keep the current framing).
    @State private var hasInteracted = false

    init(
        image: CGImage,
        title: String,
        aspects: [CropGeometry.Aspect],
        initialAspect: CropGeometry.Aspect? = nil,
        isSaving: Bool = false,
        onCancel: @escaping () -> Void,
        onSave: @escaping (CropEditResult) -> Void
    ) {
        self.image = image
        self.title = title
        self.aspects = aspects.isEmpty ? [.original] : aspects
        self.isSaving = isSaving
        self.onCancel = onCancel
        self.onSave = onSave
        _aspect = State(initialValue: initialAspect ?? self.aspects[0])
    }

    private var imageSize: CGSize { PhotoEditing.pixelSize(image) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let frame = CropGeometry.frameSize(
                        ratio: aspect.ratio(for: imageSize),
                        fitting: CGSize(width: proxy.size.width - 32, height: proxy.size.height - 16)
                    )
                    cropCanvas(frame: frame, container: proxy.size)
                        .onAppear { lastFrame = frame }
                        .onChange(of: frame) { _, newFrame in lastFrame = newFrame }
                }
                controls
            }
            .padding(.bottom, 12)
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CropEditorCopy.cancel, action: onCancel)
                        .disabled(isSaving)
                        .accessibilityIdentifier("crop.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel(CropEditorCopy.saving)
                    } else {
                        Button(CropEditorCopy.save) { save() }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("crop.save")
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Canvas

    private func cropCanvas(frame: CGSize, container: CGSize) -> some View {
        let liveZoom = CropGeometry.clampedZoom(zoom * gestureZoom)
        let liveOffset = CropGeometry.clampedOffset(
            CGSize(width: offset.width + gestureTranslation.width, height: offset.height + gestureTranslation.height),
            imageSize: imageSize, frame: frame, zoom: liveZoom
        )
        let scale = CropGeometry.displayScale(imageSize: imageSize, frame: frame, zoom: liveZoom)
        return ZStack {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize.width * scale, height: imageSize.height * scale)
                .offset(liveOffset)
            // Dim outside the frame; the frame itself stays clear.
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .mask {
                    Rectangle()
                        .overlay {
                            Rectangle()
                                .frame(width: frame.width, height: frame.height)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
                .allowsHitTesting(false)
        }
        // Size to the canvas before clipping: a zoomed photo must not spill under controls
        // or turn their surroundings into a drag area.
        .frame(width: container.width, height: container.height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .updating($gestureTranslation) { value, state, _ in state = value.translation }
                    .onChanged { _ in hasInteracted = true }
                    .onEnded { value in
                        let current = CropGeometry.clampedZoom(zoom * gestureZoom)
                        offset = CropGeometry.clampedOffset(
                            CGSize(width: offset.width + value.translation.width,
                                   height: offset.height + value.translation.height),
                            imageSize: imageSize, frame: frame, zoom: current
                        )
                    },
                MagnificationGesture()
                    .updating($gestureZoom) { value, state, _ in state = value }
                    .onChanged { _ in hasInteracted = true }
                    .onEnded { value in
                        zoom = CropGeometry.clampedZoom(zoom * value)
                        offset = CropGeometry.clampedOffset(offset, imageSize: imageSize, frame: frame, zoom: zoom)
                    }
            )
        )
        .onChange(of: zoom) { _, newZoom in
            // Any zoom change counts, including VoiceOver adjustments of the slider.
            hasInteracted = true
            offset = CropGeometry.clampedOffset(offset, imageSize: imageSize, frame: frame, zoom: newZoom)
        }
        .accessibilityElement()
        .accessibilityLabel(CropEditorCopy.canvasLabel)
        .accessibilityValue(CropEditorCopy.zoomValue(zoom))
        .accessibilityHint(CropEditorCopy.canvasHint)
        .accessibilityAdjustableAction { direction in
            hasInteracted = true
            switch direction {
            case .increment: zoom = CropGeometry.clampedZoom(zoom + 0.25)
            case .decrement: zoom = CropGeometry.clampedZoom(zoom - 0.25)
            @unknown default: break
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            if aspects.count > 1 {
                Picker(CropEditorCopy.shape, selection: $aspect) {
                    ForEach(aspects) { option in
                        Text(CropEditorCopy.label(for: option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(CropEditorCopy.shape)
                .onChange(of: aspect) { _, _ in
                    hasInteracted = true
                    offset = .zero
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
                Slider(value: $zoom, in: 1...CropGeometry.maxZoom) { editing in
                    if editing { hasInteracted = true }
                }
                .accessibilityLabel(CropEditorCopy.zoom)
                .accessibilityValue(CropEditorCopy.zoomValue(zoom))
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityHidden(true)
            }
            Button(CropEditorCopy.reset) {
                hasInteracted = true
                offset = .zero
                zoom = 1
            }
            .frame(minHeight: 44)
            .foregroundStyle(.white)
            .accessibilityIdentifier("crop.reset")
        }
        .padding(.horizontal, 20)
        .disabled(isSaving)
        .environment(\.colorScheme, .dark)
    }

    private func save() {
        let rect = CropGeometry.pixelRect(imageSize: imageSize, frame: lastFrame, zoom: zoom, offset: offset)
        onSave(
            CropEditResult(
                pixelRect: rect,
                aspect: aspect,
                isFullImage: CropGeometry.isFullImage(rect, imageSize: imageSize),
                isUntouched: !hasInteracted
            )
        )
    }
}

/// Holds a normalized bitmap for a presentation. Identifiable so `.sheet(item:)` /
/// `.fullScreenCover(item:)` can present exactly one editor at a time.
struct CropEditorPayload: Identifiable {
    let id = UUID()
    let image: CGImage
}
