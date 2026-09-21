import XCTest
@testable import PersonalStylist

/// Demonstration coverage for #220 slice A — recording stub + construction/dispatch seam.
final class OutfitEngineClientStubTests: XCTestCase {
    override func tearDown() {
        EngineURLSessionStub.tearDownClientHooks()
        super.tearDown()
    }

    func testRecordingStubReturnsScriptedGenerateResponse() async throws {
        let outfitId = UUID().uuidString.lowercased()
        let body = Data("""
        {"outfitId":"\(outfitId)","assignments":[{"slot":"TOP","garmentId":"\(UUID().uuidString.lowercased())","isAnchor":true}]}
        """.utf8)

        EngineURLSessionStub.installClientHooks { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url?.path.hasSuffix("/v1/outfit/generate") == true)
            return .http(status: 200, body: body)
        }

        let garments = try Self.readyFixtureGarments(minCount: 3)
        let anchor = garments[0].id
        let response = try await OutfitEngineClient.generate(
            garments: garments,
            sets: [],
            anchorId: anchor,
            flight: OutfitEngineClient.EngineDataTask()
        )
        XCTAssertEqual(response.outfitId.lowercased(), outfitId)

        let recorded = RecordingURLProtocol.recorded
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].method, "POST")
        XCTAssertTrue(recorded[0].path.hasSuffix("/v1/outfit/generate"))
        XCTAssertNotNil(recorded[0].body)
        XCTAssertFalse(
            recorded.contains { $0.path.contains("attribute") },
            "AC-B4: zero AttributeRequest traffic on generate"
        )
    }

    func testStubTransportErrorSurfacesAsClientTransport() async {
        EngineURLSessionStub.installClientHooks { _ in
            .transportError(URLError(.notConnectedToInternet))
        }
        let garments = (try? Self.readyFixtureGarments(minCount: 3)) ?? []
        guard let anchor = garments.first?.id else {
            return XCTFail("fixture garments required")
        }
        do {
            _ = try await OutfitEngineClient.generate(
                garments: garments,
                sets: [],
                anchorId: anchor,
                flight: OutfitEngineClient.EngineDataTask()
            )
            XCTFail("expected transport error")
        } catch OutfitEngineClient.ClientError.transport {
            // expected
        } catch {
            XCTFail("unexpected: \(error)")
        }
        XCTAssertEqual(RecordingURLProtocol.recorded.count, 1)
    }

    func testFailClosedBeforeConstructionLeavesProtocolEmpty() async {
        // Remote HTTPS + no token → never builds URLRequest (auth gate).
        OutfitEngineClient.resetTestHooks()
        OutfitEngineClient.baseURLOverride = URL(string: "https://engine.test")!
        _ = DeviceTokenStore.clear()

        var lifecycle: [OutfitEngineClient.RequestLifecycleEvent] = []
        OutfitEngineClient.requestLifecycleObserver = { lifecycle.append($0) }

        EngineURLSessionStub.installClientHooks { _ in
            XCTFail("URL loading must not start when token missing")
            return .transportError(URLError(.badURL))
        }
        // Re-apply remote override after install (install sets loopback).
        OutfitEngineClient.baseURLOverride = URL(string: "https://engine.test")!

        do {
            _ = try await OutfitEngineClient.generate(
                garments: [],
                sets: [],
                anchorId: UUID(),
                flight: OutfitEngineClient.EngineDataTask()
            )
            XCTFail("expected missingDeviceToken")
        } catch OutfitEngineClient.ClientError.missingDeviceToken {
            // expected
        } catch {
            XCTFail("unexpected: \(error)")
        }

        XCTAssertTrue(RecordingURLProtocol.recorded.isEmpty, "URLProtocol must see nothing")
        XCTAssertTrue(lifecycle.isEmpty, "request was never constructed")
    }

    func testCancelBeforeResumeIsConstructedButNotDispatched() async throws {
        EngineURLSessionStub.installClientHooks { _ in
            XCTFail("must not enter URL loading when cancelled before resume")
            return .hang
        }

        var lifecycle: [OutfitEngineClient.RequestLifecycleEvent] = []
        OutfitEngineClient.requestLifecycleObserver = { lifecycle.append($0) }

        let garments = try Self.readyFixtureGarments(minCount: 3)
        let flight = OutfitEngineClient.EngineDataTask()
        flight.cancel()

        do {
            _ = try await OutfitEngineClient.generate(
                garments: garments,
                sets: [],
                anchorId: garments[0].id,
                flight: flight
            )
            XCTFail("expected cancelled transport")
        } catch OutfitEngineClient.ClientError.transport {
            // expected
        } catch {
            XCTFail("unexpected: \(error)")
        }

        XCTAssertTrue(RecordingURLProtocol.recorded.isEmpty)
        XCTAssertEqual(lifecycle.map(\.phase), [.constructed])
        XCTAssertTrue(lifecycle[0].path.hasSuffix("/v1/outfit/generate"))
    }

    func testLatencyStubDelaysResponse() async throws {
        RecordingURLProtocol.latencyNanoseconds = 50_000_000 // 50 ms
        let body = Data(#"{"outfitId":"00000000-0000-0000-0000-000000000001","assignments":[]}"#.utf8)
        EngineURLSessionStub.installClientHooks { _ in .http(status: 200, body: body) }
        RecordingURLProtocol.latencyNanoseconds = 50_000_000

        let garments = try Self.readyFixtureGarments(minCount: 3)
        let started = ContinuousClock.now
        _ = try await OutfitEngineClient.generate(
            garments: garments,
            sets: [],
            anchorId: garments[0].id,
            flight: OutfitEngineClient.EngineDataTask()
        )
        let elapsed = started.duration(to: .now)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(40))
    }

    private static func readyFixtureGarments(minCount: Int) throws -> [StubGarment] {
        let ready = FixtureWardrobeLoader.loadGarments().filter(\.isReady)
        guard ready.count >= minCount else {
            throw NSError(domain: "OutfitEngineClientStubTests", code: 1)
        }
        return Array(ready.prefix(max(minCount, 8)))
    }
}
