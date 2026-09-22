import XCTest
@testable import PersonalStylist

final class DeviceTokenStoreTests: XCTestCase {
    /// Synthetic Keychain services touched by a test; every one is deleted in tearDown.
    private var keychainServices: [String] = []

    override func setUp() {
        super.setUp()
        DeviceTokenStore.resetTestHooks()
        DeviceTokenStore.useTestMemory()
        DeviceTokenEnrollment.resetTestHooks()
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        for service in keychainServices {
            _ = DeviceTokenStore.Keychain(service: service, legacyService: service).clear()
        }
        keychainServices = []
        RecordingURLProtocol.reset()
        DeviceTokenEnrollment.resetTestHooks()
        DeviceTokenStore.resetTestHooks()
        super.tearDown()
    }

    // MARK: - Service derivation

    func testKeychainServiceFollowsHostBundleIdentifier() throws {
        // Hosted unit tests run inside the app, so Bundle.main is the app bundle.
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertEqual(DeviceTokenStore.service, bundleID + ".device-token")
        XCTAssertEqual(DeviceTokenStore.service, DeviceTokenStore.service(forBundleIdentifier: bundleID))
        XCTAssertEqual(DeviceTokenStore.keychain.service, DeviceTokenStore.service)
        XCTAssertEqual(DeviceTokenStore.keychain.legacyService, DeviceTokenStore.legacyService)
        XCTAssertTrue(DeviceTokenStore.service.hasSuffix(".device-token"))
        XCTAssertFalse(DeviceTokenStore.service.hasPrefix("."))
    }

    func testServiceDefaultPinsLegacyName() {
        XCTAssertEqual(
            DeviceTokenStore.service(forBundleIdentifier: nil),
            "com.example.PersonalStylist.device-token"
        )
        XCTAssertEqual(
            DeviceTokenStore.service(forBundleIdentifier: "com.example.PersonalStylist"),
            "com.example.PersonalStylist.device-token"
        )
        XCTAssertEqual(DeviceTokenStore.legacyService, "com.example.PersonalStylist.device-token")
        XCTAssertFalse(DeviceTokenStore.Keychain(bundleIdentifier: nil).migratesFromLegacy)
        XCTAssertFalse(
            DeviceTokenStore.Keychain(bundleIdentifier: "com.example.PersonalStylist").migratesFromLegacy
        )
    }

    func testServiceFollowsDistinctBundleIdentifier() {
        XCTAssertEqual(
            DeviceTokenStore.service(forBundleIdentifier: "com.example.alt"),
            "com.example.alt.device-token"
        )
        let keychain = DeviceTokenStore.Keychain(bundleIdentifier: "com.example.alt")
        XCTAssertEqual(keychain.service, "com.example.alt.device-token")
        XCTAssertEqual(keychain.legacyService, "com.example.PersonalStylist.device-token")
        XCTAssertTrue(keychain.migratesFromLegacy)
    }

    // MARK: - Legacy-service migration
    //
    // The unsigned test host cannot write real Keychain items (that is why the store has
    // `useTestMemory`), so the migration logic runs against in-memory items keyed by
    // service. Service names are unique and synthetic; `testSecurityItemsRoundTrip` is the
    // one real-Keychain check and skips visibly when the host cannot write.

    func testLoadMigratesLegacyItemToDerivedService() {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("legacy-opaque-token", service: legacy))
        items.log = []
        let migrating = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items)

        XCTAssertEqual(migrating.load(), "legacy-opaque-token")
        XCTAssertEqual(items.values[derived], "legacy-opaque-token", "token must now live under the derived service")
        XCTAssertNil(items.values[legacy], "legacy item must be deleted after a successful copy")
        XCTAssertEqual(items.log, [
            .read(derived), .read(legacy), .write(derived), .delete(legacy),
        ], "copy first, delete legacy only afterwards")

        // Second load is served from the derived service; nothing else is touched.
        items.log = []
        XCTAssertEqual(migrating.load(), "legacy-opaque-token")
        XCTAssertEqual(items.log, [.read(derived)])
    }

    func testLoadKeepsLegacyItemWhenDerivedWriteFails() {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("legacy-opaque-token", service: legacy))
        items.rejectWrites = true
        let migrating = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items)

        XCTAssertEqual(migrating.load(), "legacy-opaque-token", "the session must survive a failed copy")
        XCTAssertNil(items.values[derived])
        XCTAssertEqual(items.values[legacy], "legacy-opaque-token", "legacy item stays for the next attempt")
        XCTAssertTrue(items.log.contains(.write(derived)), "the copy must have been attempted")
        XCTAssertFalse(items.log.contains(.delete(legacy)), "legacy item is never deleted after a failed copy")
    }

    func testLoadPrefersExistingDerivedItemAndLeavesLegacyUntouched() {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("derived-token", service: derived))
        XCTAssertTrue(items.write("stale-legacy-token", service: legacy))
        items.log = []
        let migrating = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items)

        XCTAssertEqual(migrating.load(), "derived-token")
        XCTAssertEqual(items.values[legacy], "stale-legacy-token", "no migration when a derived item exists")
        XCTAssertEqual(items.log, [.read(derived)], "the legacy service is not even consulted")
    }

    func testLoadDoesNotMigrateWhenDerivedServiceEqualsLegacy() {
        let items = MemoryItems()
        let service = makeService("same")
        let keychain = DeviceTokenStore.Keychain(service: service, legacyService: service, items: items)
        XCTAssertFalse(keychain.migratesFromLegacy)

        XCTAssertNil(keychain.load())
        XCTAssertEqual(items.log, [.read(service)], "no second lookup when the services are the same")
        XCTAssertTrue(keychain.save("plain-token"))
        XCTAssertEqual(keychain.load(), "plain-token")
        XCTAssertTrue(keychain.clear())
        XCTAssertNil(keychain.load())
        XCTAssertEqual(items.log, [
            .read(service), .write(service), .read(service), .delete(service), .read(service),
        ], "only the one service is touched, and clear deletes it once")
    }

    func testLoadReturnsNilWhenNeitherServiceHasAnItem() {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        let migrating = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items)

        XCTAssertNil(migrating.load())
        XCTAssertEqual(items.log, [.read(derived), .read(legacy)])
        XCTAssertTrue(items.values.isEmpty)
    }

    func testClearRemovesLegacyItemSoItCannotResurface() {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("legacy-opaque-token", service: legacy))
        items.log = []
        let migrating = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items)

        XCTAssertTrue(migrating.clear())
        XCTAssertEqual(items.log, [.delete(derived), .delete(legacy)])
        XCTAssertNil(migrating.load(), "a cleared token must not be migrated back from the legacy item")
        XCTAssertTrue(items.values.isEmpty)
    }

    func testSecurityItemsRoundTrip() throws {
        let items = DeviceTokenStore.SecurityItems()
        let service = makeService("security")
        guard items.write("probe-token", service: service) else {
            throw XCTSkip("Keychain writes are unavailable in this test host")
        }
        XCTAssertEqual(items.read(service: service), "probe-token")
        XCTAssertTrue(items.delete(service: service))
        XCTAssertNil(items.read(service: service))
        XCTAssertTrue(items.delete(service: service), "deleting a missing item is not an error")
    }

    // MARK: - Helpers

    private func makeMigrationServices() -> (derived: String, legacy: String) {
        (makeService("derived"), makeService("legacy"))
    }

    /// Unique synthetic service name, registered for tearDown cleanup of any real Keychain item.
    private func makeService(_ label: String) -> String {
        let service = "com.example.tests.\(label).\(UUID().uuidString).device-token"
        keychainServices.append(service)
        return service
    }

    /// In-memory `DeviceTokenStore.Items` that records every primitive call in order.
    private final class MemoryItems: DeviceTokenStore.Items {
        enum Call: Equatable {
            case read(String)
            case write(String)
            case delete(String)
        }

        var values: [String: String] = [:]
        var log: [Call] = []
        var rejectWrites = false

        func read(service: String) -> String? {
            log.append(.read(service))
            return values[service]
        }

        func write(_ token: String, service: String) -> Bool {
            log.append(.write(service))
            if rejectWrites { return false }
            values[service] = token
            return true
        }

        func delete(service: String) -> Bool {
            log.append(.delete(service))
            values[service] = nil
            return true
        }
    }

    func testSaveLoadClearRoundTrip() {
        XCTAssertFalse(DeviceTokenStore.hasToken)
        XCTAssertTrue(DeviceTokenStore.save("opaque-test-token"))
        XCTAssertTrue(DeviceTokenStore.hasToken)
        XCTAssertEqual(DeviceTokenStore.load(), "opaque-test-token")
        XCTAssertTrue(DeviceTokenStore.clear())
        XCTAssertFalse(DeviceTokenStore.hasToken)
    }

    func testSaveTrimsAndRejectsEmpty() {
        XCTAssertFalse(DeviceTokenStore.save("   "))
        XCTAssertFalse(DeviceTokenStore.hasToken)
        XCTAssertTrue(DeviceTokenStore.save("  pasted-token  "))
        XCTAssertEqual(DeviceTokenStore.load(), "pasted-token")
    }

    func testParseDeviceTokenFromSuccessJSON() throws {
        let data = try XCTUnwrap(
            #"{"deviceToken":"issued-1","issuedAt":"2026-09-20T00:00:00Z"}"#.data(using: .utf8)
        )
        XCTAssertEqual(DeviceTokenEnrollment.parseDeviceToken(from: data), "issued-1")

        let padded = try XCTUnwrap(#"{"deviceToken":"  issued-2  "}"#.data(using: .utf8))
        XCTAssertEqual(DeviceTokenEnrollment.parseDeviceToken(from: padded), "issued-2")

        let empty = try XCTUnwrap(#"{"deviceToken":"  "}"#.data(using: .utf8))
        XCTAssertNil(DeviceTokenEnrollment.parseDeviceToken(from: empty))

        let missing = try XCTUnwrap(#"{"issuedAt":"2026-09-20T00:00:00Z"}"#.data(using: .utf8))
        XCTAssertNil(DeviceTokenEnrollment.parseDeviceToken(from: missing))
    }

    func testEnrollAndSaveSuccessWritesToken() async throws {
        let body = try XCTUnwrap(
            #"{"deviceToken":"enrolled-opaque","issuedAt":"2026-09-20T00:00:00Z"}"#.data(using: .utf8)
        )
        RecordingURLProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/auth/device")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer enroll-secret")
            return .http(status: 201, body: body)
        }
        DeviceTokenEnrollment.urlSession = EngineURLSessionStub.makeSession()

        let ok = await DeviceTokenEnrollment.enrollAndSave(
            baseURL: URL(string: "https://example.test")!,
            enrollmentSecret: "  enroll-secret  "
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(DeviceTokenStore.load(), "enrolled-opaque")
        XCTAssertEqual(RecordingURLProtocol.recorded.count, 1)
    }

    func testEnrollFailureLeavesTokenUnchanged() async {
        XCTAssertTrue(DeviceTokenStore.save("existing-token"))
        RecordingURLProtocol.install { _ in
            .http(status: 401, body: Data(#"{"title":"Unauthorized","status":401}"#.utf8))
        }
        DeviceTokenEnrollment.urlSession = EngineURLSessionStub.makeSession()

        let ok = await DeviceTokenEnrollment.enrollAndSave(
            baseURL: URL(string: "https://example.test")!,
            enrollmentSecret: "bad-secret"
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(DeviceTokenStore.load(), "existing-token")
    }

    func testEnrollEmptySecretDoesNotNetwork() async {
        RecordingURLProtocol.install { _ in
            XCTFail("must not hit network for empty secret")
            return .http(status: 500, body: Data())
        }
        DeviceTokenEnrollment.urlSession = EngineURLSessionStub.makeSession()

        do {
            _ = try await DeviceTokenEnrollment.fetchDeviceToken(
                baseURL: URL(string: "https://example.test")!,
                enrollmentSecret: "   "
            )
            XCTFail("expected emptySecret")
        } catch DeviceTokenEnrollment.EnrollmentError.emptySecret {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(RecordingURLProtocol.recorded.isEmpty)
        XCTAssertFalse(DeviceTokenStore.hasToken)
    }
}
