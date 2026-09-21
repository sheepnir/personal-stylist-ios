import Combine
import UIKit

/// Payload-bearing camera cover. Preview is impossible without an image.
enum CameraIntakeCover: Identifiable {
    case capture
    case preview(CameraPreviewPayload)

    var id: String {
        switch self {
        case .capture:
            return "capture"
        case .preview(let payload):
            return "preview-\(payload.pending.id.uuidString)"
        }
    }

    /// Every case has real content — never an empty full-screen branch.
    var isRenderable: Bool {
        switch self {
        case .capture:
            return true
        case .preview:
            return true
        }
    }

    var previewPayload: CameraPreviewPayload? {
        if case .preview(let payload) = self { return payload }
        return nil
    }
}

extension CameraIntakeCover: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.capture, .capture):
            return true
        case let (.preview(left), .preview(right)):
            return left == right
        default:
            return false
        }
    }
}

/// Image is required. Callers cannot present a preview cover from pending alone.
struct CameraPreviewPayload: Equatable {
    let pending: CameraPending
    let image: UIImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pending == rhs.pending && lhs.image === rhs.image
    }
}

enum CameraIntakeAlert: Equatable, Identifiable {
    case persist(String)
    case permission(CameraAuthorizationState)

    var id: String {
        switch self {
        case .persist(let message):
            return "persist-\(message)"
        case .permission(let state):
            return "permission-\(String(describing: state))"
        }
    }

    var title: String {
        switch self {
        case .persist:
            return "Couldn’t use that photo"
        case .permission(let state):
            return CameraIntakeCopy.fallbackTitle(for: state)
        }
    }

    var message: String {
        switch self {
        case .persist(let message):
            return message
        case .permission(let state):
            return CameraIntakeCopy.fallbackMessage(for: state)
        }
    }

    var showsOpenSettings: Bool {
        if case .permission(let state) = self {
            return CameraPermissionPolicy.showsOpenSettings(for: state)
        }
        return false
    }

    var showsTryAgain: Bool {
        if case .persist = self { return true }
        return false
    }
}

enum CameraIntakeEvent: Equatable {
    case startCapture
    case nativeUsePhoto
    case nativeCancel
    case coverDismissed
    case persistSucceeded(CameraPending)
    case persistFailed(String)
    case previewUsePhoto
    case previewRetake
    case previewCancel
    case detailsDismissed
    case clearAlert
    case permissionFallback(CameraAuthorizationState)
}

enum CameraIntakeEffect: Equatable {
    case persistIncomingImage
    case abandonPending(UUID)
}

/// Serialized camera presentation. Native Use Photo dismisses first; persist and
/// preview wait for `coverDismissed`. No sleep or dispatch delays.
struct CameraIntakeState: Equatable {
    var cover: CameraIntakeCover?
    var queuedCover: CameraIntakeCover?
    var details: CameraPending?
    var alert: CameraIntakeAlert?
    var incomingImage: UIImage?
    var pending: CameraPending?
    var queuedDetails: CameraPending?
    /// Bumped on start / cancel / retake so a late persist cannot resurrect UI.
    var sessionID: UInt = 0
    var persistSessionID: UInt?
    /// Capture cover is dismissing; a later `onDismiss` must not look like a preview swipe.
    var dismissingCapture = false
    /// Drop a duplicate capture `onDismiss` after preview is already up.
    var suppressStaleCoverDismiss = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cover == rhs.cover
            && lhs.queuedCover == rhs.queuedCover
            && lhs.details == rhs.details
            && lhs.alert == rhs.alert
            && lhs.incomingImage === rhs.incomingImage
            && lhs.pending == rhs.pending
            && lhs.queuedDetails == rhs.queuedDetails
            && lhs.sessionID == rhs.sessionID
            && lhs.persistSessionID == rhs.persistSessionID
            && lhs.dismissingCapture == rhs.dismissingCapture
            && lhs.suppressStaleCoverDismiss == rhs.suppressStaleCoverDismiss
    }
}

enum CameraIntakePresentation {
    @discardableResult
    static func reduce(_ state: inout CameraIntakeState, _ event: CameraIntakeEvent) -> [CameraIntakeEffect] {
        switch event {
        case .startCapture:
            return reduceStartCapture(&state)
        case .nativeUsePhoto:
            return reduceNativeUsePhoto(&state)
        case .nativeCancel:
            return reduceAbandonSession(&state, queueCapture: false)
        case .coverDismissed:
            return reduceCoverDismissed(&state)
        case .persistSucceeded(let pending):
            return reducePersistSucceeded(&state, pending: pending)
        case .persistFailed(let message):
            return reducePersistFailed(&state, message: message)
        case .previewUsePhoto:
            return reducePreviewUsePhoto(&state)
        case .previewRetake:
            return reduceAbandonSession(&state, queueCapture: true)
        case .previewCancel:
            return reduceAbandonSession(&state, queueCapture: false)
        case .detailsDismissed:
            state.details = nil
            state.pending = nil
            state.queuedDetails = nil
            return []
        case .clearAlert:
            state.alert = nil
            return []
        case .permissionFallback(let authorization):
            state.alert = .permission(authorization)
            return []
        }
    }

    /// Shared persist seam for the view and tests. Reads the captured image at
    /// call time so a later cancel cannot swap in a different payload.
    static func persistEvent(
        image: UIImage?,
        begin: (Data) async throws -> CameraPending
    ) async -> CameraIntakeEvent {
        guard let image, let data = image.jpegData(compressionQuality: 0.82) else {
            return .persistFailed(CameraIntakeCopy.captureFailed)
        }
        do {
            let pending = try await begin(data)
            return .persistSucceeded(pending)
        } catch {
            return .persistFailed(CameraIntakeCopy.persistFailure(from: error))
        }
    }

    private static func reduceStartCapture(_ state: inout CameraIntakeState) -> [CameraIntakeEffect] {
        state.sessionID += 1
        state.persistSessionID = nil
        state.dismissingCapture = false
        state.suppressStaleCoverDismiss = false
        state.incomingImage = nil
        state.queuedDetails = nil
        state.details = nil
        state.alert = nil
        var effects: [CameraIntakeEffect] = []
        if let pending = state.pending {
            effects.append(.abandonPending(pending.id))
            state.pending = nil
        }
        if state.cover != nil {
            state.queuedCover = .capture
            state.cover = nil
        } else {
            state.queuedCover = nil
            state.cover = .capture
        }
        return effects
    }

    private static func reduceNativeUsePhoto(_ state: inout CameraIntakeState) -> [CameraIntakeEffect] {
        // Dismiss only. Preview and persist wait for coverDismissed.
        if state.incomingImage == nil {
            state.cover = nil
            state.dismissingCapture = false
            return []
        }
        state.cover = nil
        state.queuedCover = nil
        state.dismissingCapture = true
        return []
    }

    private static func reduceCoverDismissed(_ state: inout CameraIntakeState) -> [CameraIntakeEffect] {
        if state.suppressStaleCoverDismiss {
            state.suppressStaleCoverDismiss = false
            state.dismissingCapture = false
            return []
        }
        if state.dismissingCapture {
            state.dismissingCapture = false
            if state.incomingImage != nil, state.persistSessionID == nil {
                state.persistSessionID = state.sessionID
                return [.persistIncomingImage]
            }
            return []
        }
        if let queued = state.queuedDetails {
            state.queuedDetails = nil
            state.details = queued
            return []
        }
        if let queued = state.queuedCover {
            state.queuedCover = nil
            state.cover = queued
            return []
        }
        if case .preview = state.cover {
            state.cover = nil
        }
        if let pending = state.pending, state.details == nil, state.cover == nil {
            state.pending = nil
            state.incomingImage = nil
            state.sessionID += 1
            state.persistSessionID = nil
            return [.abandonPending(pending.id)]
        }
        return []
    }

    private static func reducePersistSucceeded(
        _ state: inout CameraIntakeState,
        pending: CameraPending
    ) -> [CameraIntakeEffect] {
        let live = state.persistSessionID == state.sessionID
        state.persistSessionID = nil
        if !live {
            state.incomingImage = nil
            return [.abandonPending(pending.id)]
        }
        guard let image = state.incomingImage else {
            state.incomingImage = nil
            state.cover = nil
            state.queuedCover = nil
            state.alert = .persist(CameraIntakeCopy.captureFailed)
            return [.abandonPending(pending.id)]
        }
        state.incomingImage = nil
        state.pending = pending
        state.queuedCover = nil
        state.cover = .preview(CameraPreviewPayload(pending: pending, image: image))
        state.suppressStaleCoverDismiss = true
        return []
    }

    private static func reducePersistFailed(
        _ state: inout CameraIntakeState,
        message: String
    ) -> [CameraIntakeEffect] {
        let live = state.persistSessionID == state.sessionID
        state.persistSessionID = nil
        state.incomingImage = nil
        state.cover = nil
        state.queuedCover = nil
        if live {
            state.alert = .persist(message)
        }
        return []
    }

    private static func reducePreviewUsePhoto(_ state: inout CameraIntakeState) -> [CameraIntakeEffect] {
        guard let pending = state.pending else {
            state.cover = nil
            return []
        }
        state.queuedDetails = pending
        state.cover = nil
        state.suppressStaleCoverDismiss = false
        return []
    }

    private static func reduceAbandonSession(
        _ state: inout CameraIntakeState,
        queueCapture: Bool
    ) -> [CameraIntakeEffect] {
        state.sessionID += 1
        state.persistSessionID = nil
        state.dismissingCapture = false
        state.suppressStaleCoverDismiss = false
        state.incomingImage = nil
        state.queuedDetails = nil
        state.details = nil
        var effects: [CameraIntakeEffect] = []
        if let pending = state.pending {
            effects.append(.abandonPending(pending.id))
            state.pending = nil
        }
        state.queuedCover = queueCapture ? .capture : nil
        state.cover = nil
        return effects
    }
}

/// Shared apply + persist path used by `CameraIntakeHost` and Wardrobe Take photo.
@MainActor
final class CameraIntakeSession: ObservableObject {
    @Published var state = CameraIntakeState()
    private(set) var model: LoopDemoModel?

    func attach(_ model: LoopDemoModel) {
        self.model = model
    }

    func apply(_ event: CameraIntakeEvent) {
        objectWillChange.send()
        let effects = CameraIntakePresentation.reduce(&state, event)
        guard let model else { return }
        for effect in effects {
            switch effect {
            case .persistIncomingImage:
                let image = state.incomingImage
                Task { await persistIncoming(image, model: model) }
            case .abandonPending(let id):
                Task { await model.abandonCameraPending(id: id) }
            }
        }
    }

    func requireModel() -> LoopDemoModel {
        guard let model else {
            preconditionFailure("CameraIntakeSession.attach must run before presenting camera chrome")
        }
        return model
    }

    private func persistIncoming(_ image: UIImage?, model: LoopDemoModel) async {
        let event = await CameraIntakePresentation.persistEvent(image: image) { data in
            try await model.beginCameraPending(jpegData: data)
        }
        apply(event)
    }
}
