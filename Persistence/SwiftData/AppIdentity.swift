import Foundation

/// Single-user local-first identity stamp for every SwiftData entity (D-13 / M0-11).
enum AppIdentity {
    /// Stable local user id (not a fixture literal — technical sentinel for single-device SoT).
    static let defaultUserId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let defaultLocale = "en_US"
    static let defaultCurrency = "USD"
}
