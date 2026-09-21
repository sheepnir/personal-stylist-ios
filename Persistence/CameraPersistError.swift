import Darwin
import Foundation

/// Typed camera-intake failures the Front End can map. Never a raw HTTP/URL string.
enum CameraPersistError: Error, Equatable, Sendable {
    case undecodableImage
    case encodeFailed
    case lowStorage
    case saveFailed
    case slotRequired
    case pendingUnavailable

    static func map(_ error: Error) -> CameraPersistError {
        if let persist = error as? CameraPersistError { return persist }
        if let store = error as? UserGarmentPhotoStore.StoreError {
            switch store {
            case .undecodable: return .undecodableImage
            case .encodeFailed: return .encodeFailed
            case .lowStorage: return .lowStorage
            case .writeFailed: return .saveFailed
            }
        }
        let ns = error as NSError
        if ns.code == NSFileWriteOutOfSpaceError { return .lowStorage }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return .lowStorage }
        return .saveFailed
    }
}

/// Test-only seams for D-73 write-then-row rollback. Production leaves these nil.
enum CameraPersistHooks {
    static var failAfterPendingFileWrite: Error?
    static var lastPendingFilePath: String?
    /// Hosted-view slow-persist only. Product serialization is SwiftUI `onDismiss`.
    static var delayNanoseconds: UInt64?

    static func reset() {
        failAfterPendingFileWrite = nil
        lastPendingFilePath = nil
        delayNanoseconds = nil
    }

    static func awaitInjectedDelay() async {
        guard let delayNanoseconds, delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

enum CameraPendingCommitBuilder {
    static func garment(
        id: UUID,
        slot: StubSlot,
        name: String?,
        imagePath: String,
        color: StubColorPrimary?,
        pattern: String?,
        surface: String?,
        formality: Int?,
        warmth: Int?
    ) -> StubGarment {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName: String
        let displayNameSource: String
        if trimmed.isEmpty {
            displayName = StubGarment.untitledName(for: slot)
            displayNameSource = "DERIVED"
        } else {
            displayName = trimmed
            displayNameSource = "USER"
        }

        var attributeSource: [String: String] = ["slot": "USER"]
        let colorOk = hasColor(color)
        if colorOk { attributeSource["color"] = "USER" }
        let patternValue = nonempty(pattern)
        if patternValue != nil { attributeSource["pattern"] = "USER" }
        let surfaceValue = nonempty(surface)
        if surfaceValue != nil { attributeSource["surface"] = "USER" }
        if formality != nil { attributeSource["formality"] = "USER" }
        if warmth != nil { attributeSource["warmth"] = "USER" }

        let ready = colorOk
            && patternValue != nil
            && surfaceValue != nil
            && formality != nil
            && warmth != nil

        return StubGarment(
            id: id,
            displayName: displayName,
            slot: slot,
            readiness: ready ? .ready : .draft,
            availability: "AVAILABLE",
            colorPrimary: colorOk ? color : nil,
            pattern: patternValue,
            surface: surfaceValue,
            imagePath: imagePath,
            formality: formality,
            warmth: warmth,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(),
            displayNameSource: displayNameSource,
            attributeSource: attributeSource
        )
    }

    private static func hasColor(_ color: StubColorPrimary?) -> Bool {
        guard let color else { return false }
        let name = color.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let family = color.family?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty || !family.isEmpty
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
