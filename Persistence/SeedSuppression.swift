import Foundation

/// Install-scoped flags that stop fixture reseed after a user-initiated clear or reset (D-70 / D-71).
/// Ordinary first install (flags unset, empty store) still seeds. Deleting the app clears the flags.
enum SeedSuppression {
    static let wardrobeKey = "ps.suppressAutomaticWardrobeSeed"
    static let profileKey = "ps.suppressAutomaticProfileSeed"

    static func isAutomaticWardrobeSeedSuppressed(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: wardrobeKey)
    }

    static func isAutomaticProfileSeedSuppressed(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: profileKey)
    }

    static func suppressAutomaticWardrobeSeed(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: wardrobeKey)
    }

    static func suppressAutomaticProfileSeed(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: profileKey)
    }

    static func shouldWriteAutomaticProfileSeed(
        hasExistingProfile: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        !hasExistingProfile && !isAutomaticProfileSeedSuppressed(in: defaults)
    }
}
