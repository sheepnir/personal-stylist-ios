import Foundation
import Security

/// Keychain-backed device token for Backend device-token auth (D-46 / #168).
/// Opaque device token only — never an OpenRouter key, never from Info.plist.
enum DeviceTokenStore {
    private static let service = "com.example.PersonalStylist.device-token"
    private static let account = "device"

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if usesTestMemory {
            testMemoryToken = trimmed
            return true
        }
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func clear() -> Bool {
        if usesTestMemory {
            testMemoryToken = ""
            return true
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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
}
