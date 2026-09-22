import XCTest
@testable import PersonalStylist

final class DeviceTokenStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DeviceTokenStore.resetTestHooks()
        DeviceTokenStore.useTestMemory()
        DeviceTokenEnrollment.resetTestHooks()
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        RecordingURLProtocol.reset()
        DeviceTokenEnrollment.resetTestHooks()
        DeviceTokenStore.resetTestHooks()
        super.tearDown()
    }

    func testKeychainServiceFollowsHostBundleIdentifier() throws {
        // Hosted unit tests run inside the app, so Bundle.main is the app bundle.
        let bundleID = try XCTUnwrap(Bundle.main.bundleIdentifier)
        XCTAssertEqual(DeviceTokenStore.service, bundleID + ".device-token")
        XCTAssertTrue(DeviceTokenStore.service.hasSuffix(".device-token"))
        XCTAssertFalse(DeviceTokenStore.service.hasPrefix("."))
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
