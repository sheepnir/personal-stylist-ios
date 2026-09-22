import Foundation
import Security

/// Keychain-backed device token for Backend device-token auth (D-46 / #168).
/// Opaque device token only — never an OpenRouter key, never from Info.plist.
enum DeviceTokenStore {
    /// Fallback only for the placeholder build; a signed app always has a bundle identifier.
    static let fallbackBundleIdentifier = "com.example.PersonalStylist"

    /// Service name earlier builds used unconditionally, regardless of bundle identifier.
    /// `load()` migrates a token found here into the derived service exactly once.
    static let legacyService = service(forBundleIdentifier: nil)

    /// Keychain service for a given bundle identifier: `<bundle id>.device-token`.
    /// `nil` (no bundle identifier) resolves to the placeholder default.
    static func service(forBundleIdentifier bundleIdentifier: String?) -> String {
        (bundleIdentifier ?? fallbackBundleIdentifier) + ".device-token"
    }

    /// Keychain service the running app uses. It follows the bundle identifier the app was
    /// built with, so a build with an overridden `PRODUCT_BUNDLE_IDENTIFIER` keeps its own
    /// token across updates. Default build: `com.example.PersonalStylist.device-token`.
    static let service = keychain.service

    /// One lock for every load / save / clear, including the whole migration sequence, so a
    /// load that has read the legacy item cannot interleave with a clear or another load.
    /// Only synchronous SecItem calls run under it; it is never held across an `await`.
    static let keychainLock = NSLock()

    /// Production Keychain binding for the running app.
    static let keychain = Keychain(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// Non-nil enables in-memory storage for unit tests (unsigned CI cannot write Keychain).
    /// Production leaves this `nil`. Empty string means "cleared but still in test mode."
    static var testMemoryToken: String?

    static func resetTestHooks() {
        testMemoryToken = nil
    }

    /// Enable in-memory token for unit tests.
    static func useTestMemory() {
        testMemoryToken = ""
    }

    private static var usesTestMemory: Bool { testMemoryToken != nil }

    static func load() -> String? {
        if usesTestMemory {
            let value = testMemoryToken ?? ""
            return value.isEmpty ? nil : value
        }
        return keychain.load()
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if usesTestMemory {
            testMemoryToken = trimmed
            return true
        }
        return keychain.save(trimmed)
    }

    @discardableResult
    static func clear() -> Bool {
        if usesTestMemory {
            testMemoryToken = ""
            return true
        }
        return keychain.clear()
    }

    /// True when storage holds a non-empty device token.
    static var hasToken: Bool {
        guard let token = load() else { return false }
        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /**
     Debug-only bootstrap (D-46 / #168): never reads Info.plist.
     1. If Keychain already has a token — no-op.
     2. Else if process env `DEVICE_TOKEN` is set — save it (Simulator scheme env).
     3. Else if process env `ENROLLMENT_SECRET` is set and `baseURL` is remote HTTPS —
        `POST /v1/auth/device` via `DeviceTokenEnrollment` and save the issued token.
     Release builds compile this out; TestFlight uses Profile → Device access (#89).
     */
    static func bootstrapDebugIfNeeded(baseURL: URL) async {
        #if DEBUG
        if hasToken { return }

        if let envToken = ProcessInfo.processInfo.environment["DEVICE_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envToken.isEmpty {
            _ = save(envToken)
            return
        }

        guard baseURL.scheme?.lowercased() == "https",
              let enrollment = ProcessInfo.processInfo.environment["ENROLLMENT_SECRET"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !enrollment.isEmpty else {
            return
        }

        _ = await DeviceTokenEnrollment.enrollAndSave(
            baseURL: baseURL,
            enrollmentSecret: enrollment
        )
        #endif
    }

    /// Generic-password items keyed by service name. Production uses the Security framework;
    /// tests inject an in-memory implementation because an unsigned test host cannot write
    /// Keychain items. The token value is never logged by either.
    protocol Items {
        func read(service: String) -> String?
        func write(_ token: String, service: String) -> Bool
        func delete(service: String) -> Bool
    }

    /// Security-framework items: one account per service, same accessibility class for every
    /// write, no access group, never synchronizable.
    struct SecurityItems: Items {
        private static let account = "device"

        private func baseQuery(service: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: Self.account,
            ]
        }

        func read(service: String) -> String? {
            var query = baseQuery(service: service)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess, let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        func write(_ token: String, service: String) -> Bool {
            let query = baseQuery(service: service)
            SecItemDelete(query as CFDictionary)
            var add = query
            add[kSecValueData as String] = Data(token.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }

        func delete(service: String) -> Bool {
            let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
    }

    /// Token binding for one derived service plus the legacy service it migrates from.
    /// Tests construct it with synthetic service names and in-memory items; production uses
    /// `DeviceTokenStore.keychain`.
    struct Keychain {
        let service: String
        let legacyService: String
        let items: any Items
        /// Serializes complete operations. Production shares `DeviceTokenStore.keychainLock`;
        /// tests may pass their own.
        let lock: NSLock

        init(
            bundleIdentifier: String?,
            legacyService: String = DeviceTokenStore.legacyService,
            items: any Items = SecurityItems(),
            lock: NSLock = DeviceTokenStore.keychainLock
        ) {
            self.init(
                service: DeviceTokenStore.service(forBundleIdentifier: bundleIdentifier),
                legacyService: legacyService,
                items: items,
                lock: lock
            )
        }

        init(
            service: String,
            legacyService: String,
            items: any Items = SecurityItems(),
            lock: NSLock = DeviceTokenStore.keychainLock
        ) {
            self.service = service
            self.legacyService = legacyService
            self.items = items
            self.lock = lock
        }

        /// True when the derived service differs from the legacy one, i.e. a legacy item can exist.
        var migratesFromLegacy: Bool { service != legacyService }

        /// Reads the token under the derived service. When none exists and the derived service
        /// differs from the legacy one, a legacy item is copied to the derived service; the legacy
        /// item is deleted only after that copy succeeded. The token is returned either way, so a
        /// failed copy is retried on the next load instead of losing the session. The whole
        /// sequence runs under the lock, so a concurrent clear or load sees either the state
        /// before or the state after it, never the middle.
        func load() -> String? {
            lock.withLock {
                if let token = items.read(service: service) { return token }
                guard migratesFromLegacy, let legacy = items.read(service: legacyService) else { return nil }
                if items.write(legacy, service: service) {
                    _ = items.delete(service: legacyService)
                }
                return legacy
            }
        }

        @discardableResult
        func save(_ token: String) -> Bool {
            lock.withLock { items.write(token, service: service) }
        }

        /// Removes the derived item and, when it differs, the legacy item too, so a cleared
        /// token cannot resurface through migration on the next load.
        @discardableResult
        func clear() -> Bool {
            lock.withLock {
                let cleared = items.delete(service: service)
                guard migratesFromLegacy else { return cleared }
                return items.delete(service: legacyService) && cleared
            }
        }
    }
}
