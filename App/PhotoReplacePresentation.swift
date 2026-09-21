import Combine
import UIKit

enum PhotoReplaceSource: Equatable {
    case photos
    case camera
}

/// Payload-bearing replace cover. Preview is impossible without an image.
enum PhotoReplaceCover: Identifiable {
    case photos
    case capture
    case preview(PhotoReplacePreviewPayload)

    var id: String {
        switch self {
        case .photos:
            return "photos"
        case .capture:
            return "capture"
        case .preview(let payload):
            return "preview-\(payload.pending.id.uuidString)"
        }
    }

    /// Every case has real content — never an empty full-screen branch.
    var isRenderable: Bool {
        switch self {
        case .photos, .capture, .preview:
            return true
        }
    }

    var previewPayload: PhotoReplacePreviewPayload? {
        if case .preview(let payload) = self { return payload }
        return nil
    }
}

extension PhotoReplaceCover: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.photos, .photos), (.capture, .capture):
            return true
        case let (.preview(left), .preview(right)):
            return left == right
        default:
            return false
        }
    }
}

/// Image is required. Callers cannot present a preview cover from pending alone.
struct PhotoReplacePreviewPayload: Equatable {
    let pending: PhotoReplacePending
    let image: UIImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pending == rhs.pending && lhs.image === rhs.image
    }
}

/// Preview handle after staging. Not a persist until Save.
struct PhotoReplacePending: Equatable, Identifiable, Sendable {
    let id: UUID
    let garmentId: UUID
    let imagePath: String
}

enum PhotoReplaceAlert: Equatable, Identifiable {
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
            return PhotoReplaceCopy.fallbackTitle(for: state)
        }
    }

    var message: String {
        switch self {
        case .persist(let message):
            return message
        case .permission(let state):
            return PhotoReplaceCopy.fallbackMessage(for: state)
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

enum PhotoReplaceEvent: Equatable {
    case chooseSource(PhotoReplaceSource, garmentId: UUID)
    case nativeUsePhoto
    case nativeCancel
    case coverDismissed
    case persistSucceeded(PhotoReplacePending)
    case persistFailed(String)
    case previewSave
    case previewChooseAnother
    case previewCancel
    case commitSucceeded
    case commitFailed(String)
    case clearAlert
    case permissionFallback(CameraAuthorizationState)
}

enum PhotoReplaceEffect: Equatable {
    case persistIncomingImage
    case abandonPending(UUID)
    case commitPending(PhotoReplacePending)
}

/// Serialized replace presentation. Native Use Photo / Photos picker dismiss first;
/// persist and preview wait for `coverDismissed`. No sleep or dispatch delays.
struct PhotoReplaceState: Equatable {
    var cover: PhotoReplaceCover?
    var queuedCover: PhotoReplaceCover?
    var alert: PhotoReplaceAlert?
    var incomingImage: UIImage?
    var pending: PhotoReplacePending?
    var queuedCommit: PhotoReplacePending?
    var garmentId: UUID?
    var lastSource: PhotoReplaceSource?
    /// Bumped on start / cancel / choose-another so a late persist cannot resurrect UI.
    var sessionID: UInt = 0
    var persistSessionID: UInt?
    var commitSessionID: UInt?
    var dismissingPicker = false
    var suppressStaleCoverDismiss = false
    /// Save is in flight — ignore overlapping source / abandon so commit cannot race.
    var commitInFlight = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cover == rhs.cover
            && lhs.queuedCover == rhs.queuedCover
            && lhs.alert == rhs.alert
            && lhs.incomingImage === rhs.incomingImage
            && lhs.pending == rhs.pending
            && lhs.queuedCommit == rhs.queuedCommit
            && lhs.garmentId == rhs.garmentId
            && lhs.lastSource == rhs.lastSource
            && lhs.sessionID == rhs.sessionID
            && lhs.persistSessionID == rhs.persistSessionID
            && lhs.commitSessionID == rhs.commitSessionID
            && lhs.dismissingPicker == rhs.dismissingPicker
            && lhs.suppressStaleCoverDismiss == rhs.suppressStaleCoverDismiss
            && lhs.commitInFlight == rhs.commitInFlight
    }
}

enum PhotoReplacePresentation {
    @discardableResult
    static func reduce(_ state: inout PhotoReplaceState, _ event: PhotoReplaceEvent) -> [PhotoReplaceEffect] {
        switch event {
        case let .chooseSource(source, garmentId):
            return reduceChooseSource(&state, source: source, garmentId: garmentId)
        case .nativeUsePhoto:
            return reduceNativeUsePhoto(&state)
        case .nativeCancel:
            if state.commitInFlight { return [] }
            return reduceAbandonSession(&state, queueSource: false)
        case .coverDismissed:
            return reduceCoverDismissed(&state)
        case .persistSucceeded(let pending):
            return reducePersistSucceeded(&state, pending: pending)
        case .persistFailed(let message):
            return reducePersistFailed(&state, message: message)
        case .previewSave:
            return reducePreviewSave(&state)
        case .previewChooseAnother:
            if state.commitInFlight { return [] }
            return reduceAbandonSession(&state, queueSource: true)
        case .previewCancel:
            if state.commitInFlight { return [] }
            return reduceAbandonSession(&state, queueSource: false)
        case .commitSucceeded:
            state.commitInFlight = false
            state.queuedCommit = nil
            state.pending = nil
            state.incomingImage = nil
            state.cover = nil
            state.queuedCover = nil
            return []
        case .commitFailed(let message):
            return reduceCommitFailed(&state, message: message)
        case .clearAlert:
            state.alert = nil
            return []
        case .permissionFallback(let authorization):
            state.alert = .permission(authorization)
            return []
        }
    }

    static func persistEvent(
        image: UIImage?,
        garmentId: UUID?,
        begin: (UUID, Data) async throws -> PhotoReplacePending
    ) async -> PhotoReplaceEvent {
        guard let garmentId else {
            return .persistFailed(PhotoReplaceCopy.saveFailed)
        }
        guard let image, let data = image.jpegData(compressionQuality: 0.82) else {
            return .persistFailed(PhotoReplaceCopy.captureFailed)
        }
        do {
            let pending = try await begin(garmentId, data)
            return .persistSucceeded(pending)
        } catch {
            return .persistFailed(PhotoReplaceCopy.persistFailure(from: error))
        }
    }

    private static func reduceChooseSource(
        _ state: inout PhotoReplaceState,
        source: PhotoReplaceSource,
        garmentId: UUID
    ) -> [PhotoReplaceEffect] {
        if state.commitInFlight { return [] }
        state.sessionID += 1
        state.persistSessionID = nil
        state.commitSessionID = nil
        state.dismissingPicker = false
        state.suppressStaleCoverDismiss = false
        state.incomingImage = nil
        state.queuedCommit = nil
        state.alert = nil
        state.garmentId = garmentId
        state.lastSource = source
        var effects: [PhotoReplaceEffect] = []
        if let pending = state.pending {
            effects.append(.abandonPending(pending.id))
            state.pending = nil
        }
        let next: PhotoReplaceCover = source == .photos ? .photos : .capture
        if state.cover != nil {
            state.queuedCover = next
            state.cover = nil
        } else {
            state.queuedCover = nil
            state.cover = next
        }
        return effects
    }

    private static func reduceNativeUsePhoto(_ state: inout PhotoReplaceState) -> [PhotoReplaceEffect] {
        if state.incomingImage == nil {
            state.cover = nil
            state.dismissingPicker = false
            return []
        }
        state.cover = nil
        state.queuedCover = nil
        state.dismissingPicker = true
        return []
    }

    private static func reduceCoverDismissed(_ state: inout PhotoReplaceState) -> [PhotoReplaceEffect] {
        if state.suppressStaleCoverDismiss {
            state.suppressStaleCoverDismiss = false
            state.dismissingPicker = false
            return []
        }
        if let queued = state.queuedCommit {
            state.queuedCommit = nil
            state.commitSessionID = state.sessionID
            return [.commitPending(queued)]
        }
        if state.dismissingPicker {
            state.dismissingPicker = false
            if state.incomingImage != nil, state.persistSessionID == nil {
                state.persistSessionID = state.sessionID
                return [.persistIncomingImage]
            }
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
        if let pending = state.pending, state.cover == nil {
            if state.commitInFlight { return [] }
            state.pending = nil
            state.incomingImage = nil
            state.sessionID += 1
            state.persistSessionID = nil
            return [.abandonPending(pending.id)]
        }
        return []
    }

    private static func reducePersistSucceeded(
        _ state: inout PhotoReplaceState,
        pending: PhotoReplacePending
    ) -> [PhotoReplaceEffect] {
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
            state.alert = .persist(PhotoReplaceCopy.captureFailed)
            return [.abandonPending(pending.id)]
        }
        state.incomingImage = nil
        state.pending = pending
        state.queuedCover = nil
        state.cover = .preview(PhotoReplacePreviewPayload(pending: pending, image: image))
        state.suppressStaleCoverDismiss = true
        return []
    }

    private static func reducePersistFailed(
        _ state: inout PhotoReplaceState,
        message: String
    ) -> [PhotoReplaceEffect] {
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

    private static func reducePreviewSave(_ state: inout PhotoReplaceState) -> [PhotoReplaceEffect] {
        guard let pending = state.pending else {
            state.cover = nil
            return []
        }
        state.queuedCommit = pending
        state.commitInFlight = true
        state.cover = nil
        state.suppressStaleCoverDismiss = false
        return []
    }

    private static func reduceCommitFailed(
        _ state: inout PhotoReplaceState,
        message: String
    ) -> [PhotoReplaceEffect] {
        let live = state.commitSessionID == state.sessionID
        state.commitInFlight = false
        state.commitSessionID = nil
        state.queuedCommit = nil
        state.incomingImage = nil
        state.cover = nil
        state.queuedCover = nil
        var effects: [PhotoReplaceEffect] = []
        if let pending = state.pending {
            effects.append(.abandonPending(pending.id))
            state.pending = nil
        }
        if live {
            state.alert = .persist(message)
        }
        return effects
    }

    private static func reduceAbandonSession(
        _ state: inout PhotoReplaceState,
        queueSource: Bool
    ) -> [PhotoReplaceEffect] {
        state.sessionID += 1
        state.persistSessionID = nil
        state.commitSessionID = nil
        state.dismissingPicker = false
        state.suppressStaleCoverDismiss = false
        state.incomingImage = nil
        state.queuedCommit = nil
        var effects: [PhotoReplaceEffect] = []
        if let pending = state.pending {
            effects.append(.abandonPending(pending.id))
            state.pending = nil
        }
        if queueSource, let source = state.lastSource {
            state.queuedCover = source == .photos ? .photos : .capture
        } else {
            state.queuedCover = nil
        }
        state.cover = nil
        return effects
    }
}

/// Shared apply + persist path used by `PhotoReplaceHost`.
@MainActor
final class PhotoReplaceSession: ObservableObject {
    @Published var state = PhotoReplaceState()
    private(set) var model: LoopDemoModel?
    private(set) var store: PersistenceStore?

    func attach(_ model: LoopDemoModel, store: PersistenceStore) {
        self.model = model
        self.store = store
        model.bindPhotoReplaceStore(store)
    }

    func apply(_ event: PhotoReplaceEvent) {
        objectWillChange.send()
        let effects = PhotoReplacePresentation.reduce(&state, event)
        for effect in effects {
            switch effect {
            case .persistIncomingImage:
                let image = state.incomingImage
                let garmentId = state.garmentId
                Task { await persistIncoming(image, garmentId: garmentId) }
            case .abandonPending(let id):
                Task { await abandon(id) }
            case .commitPending(let pending):
                Task { await commit(pending) }
            }
        }
    }

    func requireModel() -> LoopDemoModel {
        guard let model else {
            preconditionFailure("PhotoReplaceSession.attach must run before presenting replace chrome")
        }
        return model
    }

    private func persistIncoming(_ image: UIImage?, garmentId: UUID?) async {
        let event = await PhotoReplacePresentation.persistEvent(image: image, garmentId: garmentId) { garmentId, data in
            try await requireModel().beginPhotoReplace(garmentId: garmentId, jpegData: data)
        }
        apply(event)
    }

    private func abandon(_ id: UUID) async {
        await model?.abandonPhotoReplace(stagingId: id)
    }

    private func commit(_ pending: PhotoReplacePending) async {
        let liveSession = state.commitSessionID ?? state.sessionID
        guard let model else {
            apply(.commitFailed(PhotoReplaceCopy.saveFailed))
            return
        }
        let persistStore = store ?? PhotoReplaceStoreBinding.store(for: model)
        guard let persistStore else {
            apply(.commitFailed(PhotoReplaceCopy.saveFailed))
            return
        }
        do {
            let garment = try await persistStore.replaceGarmentPhoto(
                garmentId: pending.garmentId,
                stagingId: pending.id
            )
            guard state.sessionID == liveSession else {
                apply(.commitSucceeded)
                return
            }
            model.applyReplacedPhoto(garment)
            apply(.commitSucceeded)
        } catch {
            apply(.commitFailed(PhotoReplaceCopy.persistFailure(from: error)))
        }
    }
}
