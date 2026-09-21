import Darwin
import Foundation

/// Typed D-74 replacement failures the Front End can map. Never a raw HTTP/URL string.
enum PhotoReplacePersistError: Error, Equatable, Sendable {
    case undecodableImage
    case encodeFailed
    case lowStorage
    case saveFailed
    case garmentUnavailable

    static func map(_ error: Error) -> PhotoReplacePersistError {
        if let persist = error as? PhotoReplacePersistError { return persist }
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

/// Test-only seams for D-74 write-then-metadata rollback. Production leaves these nil.
enum PhotoReplacePersistHooks {
    static var failAfterStagingFileWrite: Error?
    static var failBeforeMetadataCommit: Error?
    static var lastStagedPath: String?
    static var delayNanoseconds: UInt64?

    static func reset() {
        failAfterStagingFileWrite = nil
        failBeforeMetadataCommit = nil
        lastStagedPath = nil
        delayNanoseconds = nil
    }

    static func awaitInjectedDelay() async {
        guard let delayNanoseconds, delayNanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

/// Store-wide replace lock. Overlapping commits/abandons on any garment cannot interleave.
actor PhotoReplaceGate {
    static let shared = PhotoReplaceGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        while busy {
            await withCheckedContinuation { waiters.append($0) }
        }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }
        return try await work()
    }
}
