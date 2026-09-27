import Foundation

/// Decides whether the core loop may open. A failure never substitutes an editable in-memory store.
enum AppStorageLaunch: Equatable {
    case ready
    case cleanStartIncomplete
    case wardrobeUnopened

    var blockedMessage: String? {
        switch self {
        case .ready:
            return nil
        case .cleanStartIncomplete:
            return StorageFailureCopy.cleanStartIncomplete
        case .wardrobeUnopened:
            return StorageFailureCopy.wardrobeUnopened
        }
    }

    static func resolve(
        cleanStart: () throws -> Void,
        openStore: () throws -> Void
    ) -> AppStorageLaunch {
        do {
            try cleanStart()
        } catch {
            return .cleanStartIncomplete
        }
        do {
            try openStore()
        } catch {
            return .wardrobeUnopened
        }
        return .ready
    }
}
