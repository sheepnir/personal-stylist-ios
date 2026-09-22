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

    // MARK: - Serialization (one lock per complete load / save / clear)

    func testClearDuringMigrationDoesNotResurrectToken() throws {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("legacy-opaque-token", service: legacy))
        items.log = []
        let keychain = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items, lock: NSLock())

        // Pause the load right after it has captured the legacy token, before it writes.
        let pause = MemoryItems.Pause(afterReadOf: legacy)
        items.pause = pause
        let loadDone = DispatchSemaphore(value: 0)
        let loaded = Box<String?>(nil)
        DispatchQueue.global().async {
            loaded.value = keychain.load()
            loadDone.signal()
        }
        try require(pause.reached.wait(timeout: .now() + 5), "load must reach the legacy read")
        items.pause = nil

        // clear() must block on the store lock while the migration is in progress.
        let clearDone = DispatchSemaphore(value: 0)
        let cleared = Box(false)
        DispatchQueue.global().async {
            cleared.value = keychain.clear()
            clearDone.signal()
        }
        XCTAssertEqual(clearDone.wait(timeout: .now() + 0.3), .timedOut, "clear must wait for the in-flight load")

        pause.resume.signal()
        try require(loadDone.wait(timeout: .now() + 5), "load must finish")
        try require(clearDone.wait(timeout: .now() + 5), "clear must finish once the load released the lock")

        XCTAssertEqual(loaded.value, "legacy-opaque-token", "the load that started before clear still returns the token")
        XCTAssertTrue(cleared.value)
        XCTAssertTrue(items.values.isEmpty, "no copy may survive a clear that ran after the load")
        XCTAssertEqual(items.log, [
            .read(derived), .read(legacy), .write(derived), .delete(legacy),
            .delete(derived), .delete(legacy),
        ], "the whole migration completes before clear's deletes")
        XCTAssertNil(keychain.load(), "nothing resurrects on the next load")
    }

    func testConcurrentLoadsMigrateExactlyOnce() throws {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("legacy-opaque-token", service: legacy))
        items.log = []
        let keychain = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items, lock: NSLock())

        let pause = MemoryItems.Pause(afterReadOf: legacy)
        items.pause = pause
        let firstDone = DispatchSemaphore(value: 0)
        let first = Box<String?>(nil)
        DispatchQueue.global().async {
            first.value = keychain.load()
            firstDone.signal()
        }
        try require(pause.reached.wait(timeout: .now() + 5), "first load must reach the legacy read")
        items.pause = nil

        let secondDone = DispatchSemaphore(value: 0)
        let second = Box<String?>(nil)
        DispatchQueue.global().async {
            second.value = keychain.load()
            secondDone.signal()
        }
        XCTAssertEqual(secondDone.wait(timeout: .now() + 0.3), .timedOut, "second load must wait for the first")

        pause.resume.signal()
        try require(firstDone.wait(timeout: .now() + 5), "first load must finish")
        try require(secondDone.wait(timeout: .now() + 5), "second load must finish")

        XCTAssertEqual(first.value, "legacy-opaque-token")
        XCTAssertEqual(second.value, "legacy-opaque-token")
        XCTAssertEqual(items.values, [derived: "legacy-opaque-token"], "exactly one derived item, legacy gone")
        XCTAssertEqual(items.log.filter { $0 == .write(derived) }.count, 1, "the token is copied once")
        XCTAssertEqual(items.log, [
            .read(derived), .read(legacy), .write(derived), .delete(legacy),
            .read(derived),
        ], "the second load is served from the derived item and touches nothing else")
    }

    func testConcurrentLoadsWithFailingWriteNeverLeaveZeroCopies() throws {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        XCTAssertTrue(items.write("legacy-opaque-token", service: legacy))
        items.rejectWrites = true
        items.log = []
        let keychain = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items, lock: NSLock())

        let pause = MemoryItems.Pause(afterReadOf: legacy)
        items.pause = pause
        let firstDone = DispatchSemaphore(value: 0)
        let first = Box<String?>(nil)
        DispatchQueue.global().async {
            first.value = keychain.load()
            firstDone.signal()
        }
        try require(pause.reached.wait(timeout: .now() + 5), "first load must reach the legacy read")
        items.pause = nil

        let secondDone = DispatchSemaphore(value: 0)
        let second = Box<String?>(nil)
        DispatchQueue.global().async {
            second.value = keychain.load()
            secondDone.signal()
        }
        pause.resume.signal()
        try require(firstDone.wait(timeout: .now() + 5), "first load must finish")
        try require(secondDone.wait(timeout: .now() + 5), "second load must finish")

        XCTAssertEqual(first.value, "legacy-opaque-token")
        XCTAssertEqual(second.value, "legacy-opaque-token")
        XCTAssertEqual(items.values, [legacy: "legacy-opaque-token"], "the legacy copy survives every failed write")
        XCTAssertFalse(items.log.contains(.delete(legacy)), "legacy is never deleted while no derived copy exists")

        // Once writes succeed again the next load completes the migration.
        items.rejectWrites = false
        XCTAssertEqual(keychain.load(), "legacy-opaque-token")
        XCTAssertEqual(items.values, [derived: "legacy-opaque-token"])
    }

    func testSaveAndClearSerializeWithEachOther() throws {
        let items = MemoryItems()
        let (derived, legacy) = makeMigrationServices()
        let keychain = DeviceTokenStore.Keychain(service: derived, legacyService: legacy, items: items, lock: NSLock())

        // Hold the lock from the test thread; save and clear on other threads must both wait.
        keychain.lock.lock()
        let saveDone = DispatchSemaphore(value: 0)
        let clearDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = keychain.save("fresh-token")
            saveDone.signal()
        }
        DispatchQueue.global().async {
            _ = keychain.clear()
            clearDone.signal()
        }
        XCTAssertEqual(saveDone.wait(timeout: .now() + 0.3), .timedOut, "save must wait for the lock")
        XCTAssertEqual(clearDone.wait(timeout: .now() + 0.3), .timedOut, "clear must wait for the lock")
        XCTAssertTrue(items.log.isEmpty, "no item is touched while the lock is held elsewhere")
        keychain.lock.unlock()
        try require(saveDone.wait(timeout: .now() + 5), "save must finish")
        try require(clearDone.wait(timeout: .now() + 5), "clear must finish")

        // Whichever order the scheduler picked, the result is one of the two serial outcomes.
        let outcome = items.values
        XCTAssertTrue(outcome.isEmpty || outcome == [derived: "fresh-token"], "interleaving produced \(outcome)")
    }

    func testProductionKeychainUsesTheSharedStoreLock() {
        XCTAssertTrue(DeviceTokenStore.keychain.lock === DeviceTokenStore.keychainLock)
        XCTAssertTrue(DeviceTokenStore.Keychain(bundleIdentifier: "com.example.alt").lock === DeviceTokenStore.keychainLock)
    }

    /// Fails and aborts the test when a semaphore wait timed out, so a broken interleaving
    /// can never hang the suite.
    private func require(_ result: DispatchTimeoutResult, _ message: String) throws {
        if result == .timedOut {
            XCTFail("Timed out: \(message)")
            throw TimedOut()
        }
    }

    private struct TimedOut: Error {}

    /// Reference cell for results written from a background queue.
    private final class Box<Value> {
        private let lock = NSLock()
        private var stored: Value
        init(_ value: Value) { stored = value }
        var value: Value {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
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

    /// In-memory `DeviceTokenStore.Items` that records every primitive call in order. Thread-safe,
    /// and can pause the caller after one specific read so tests can interleave operations.
    private final class MemoryItems: DeviceTokenStore.Items {
        enum Call: Equatable {
            case read(String)
            case write(String)
            case delete(String)
        }

        /// Pauses the thread that reads `service`: it signals `reached`, then blocks on `resume`
        /// (bounded, so a broken test cannot hang the suite).
        final class Pause {
            let service: String
            let reached = DispatchSemaphore(value: 0)
            let resume = DispatchSemaphore(value: 0)
            init(afterReadOf service: String) { self.service = service }
        }

        private let state = NSLock()
        private var storedValues: [String: String] = [:]
        private var storedLog: [Call] = []
        private var storedRejectWrites = false
        private var storedPause: Pause?

        var values: [String: String] {
            get { state.withLock { storedValues } }
            set { state.withLock { storedValues = newValue } }
        }
        var log: [Call] {
            get { state.withLock { storedLog } }
            set { state.withLock { storedLog = newValue } }
        }
        var rejectWrites: Bool {
            get { state.withLock { storedRejectWrites } }
            set { state.withLock { storedRejectWrites = newValue } }
        }
        var pause: Pause? {
            get { state.withLock { storedPause } }
            set { state.withLock { storedPause = newValue } }
        }

        func read(service: String) -> String? {
            let (value, pause): (String?, Pause?) = state.withLock {
                storedLog.append(.read(service))
                return (storedValues[service], storedPause?.service == service ? storedPause : nil)
            }
            if let pause {
                pause.reached.signal()
                _ = pause.resume.wait(timeout: .now() + 5)
            }
            return value
        }

        func write(_ token: String, service: String) -> Bool {
            state.withLock {
                storedLog.append(.write(service))
                if storedRejectWrites { return false }
                storedValues[service] = token
                return true
            }
        }

        func delete(service: String) -> Bool {
            state.withLock {
                storedLog.append(.delete(service))
                storedValues[service] = nil
                return true
            }
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
