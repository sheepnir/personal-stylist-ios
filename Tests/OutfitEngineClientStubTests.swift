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

    // MARK: - #34 device access (model + HTTPS stubs)

    @MainActor
    func test401OnGenerateWithNoOutfitSetsAccessStateA1() async throws {
        let model = try await makeModelForDeviceAccessTests()
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 401, body: Data())
            }
            return .http(status: 500, body: Data())
        }
        let ok = await model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertFalse(ok)
        XCTAssertTrue(model.deviceAccessRejected)
        XCTAssertNil(model.outfit)
        XCTAssertEqual(model.generateFailureMessage, DressingCopy.deviceAccessRejectedTitle)
        XCTAssertNotEqual(model.generateFailureSubtitle, DressingCopy.generateServiceError)
    }

    @MainActor
    func test401OnTryAnotherKeepsPriorOutfitA2() async throws {
        let model = try await makeModelForDeviceAccessTests()
        let successBody = try generateSuccessBody(anchorId: model.selectedGarment!.id)
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 200, body: successBody)
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertTrue(await model.buildDemoOutfit(intent: .firstBuild))
        let prior = try XCTUnwrap(model.outfit)
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 401, body: Data())
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertFalse(await model.tryAnotherOutfit())
        XCTAssertTrue(model.deviceAccessRejected)
        XCTAssertEqual(model.outfit?.id, prior.id)
        XCTAssertEqual(model.generateFailureSubtitle, DressingCopy.deviceAccessRejectedWithOutfit)
    }

    @MainActor
    func test401OnAlternativesSetsAccessStateA3() async throws {
        let model = try await makeModelForDeviceAccessTests()
        let garments = try DeviceAccessTestFixtures.readyGarments()
        let bottom = garments[1]
        let successBody = try generateSuccessBody(
            anchorId: model.selectedGarment!.id,
            secondGarmentId: bottom.id
        )
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 200, body: successBody)
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertTrue(await model.buildDemoOutfit(intent: .firstBuild))
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/alternatives") == true {
                return .http(status: 401, body: Data())
            }
            return .http(status: 500, body: Data())
        }
        await model.alternatives(for: .bottom)
        XCTAssertTrue(model.deviceAccessRejected)
        XCTAssertTrue(model.swapAlternatives.isEmpty)
        XCTAssertNotEqual(model.swapSheetDetail, "Couldn’t rank swaps. Try again.")
        XCTAssertFalse(
            model.swapAlternatives.contains { $0.reason == "Stub fallback — engine unreachable" }
        )
    }

    @MainActor
    func test503AuthUnavailableDoesNotSetAccessFlag() async throws {
        let model = try await makeModelForDeviceAccessTests()
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                let body = Data(#"{"code":"AUTH_UNAVAILABLE","status":503}"#.utf8)
                return .http(status: 503, body: body)
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertFalse(await model.buildDemoOutfit(intent: .firstBuild))
        XCTAssertFalse(model.deviceAccessRejected)
        XCTAssertEqual(model.generateFailureMessage, DressingCopy.generateServiceError)
    }

    @MainActor
    func testSwapTransportStillShowsLocalSuggestions() async throws {
        let model = try await makeModelForDeviceAccessTests()
        let garments = try DeviceAccessTestFixtures.readyGarments()
        let successBody = try generateSuccessBody(
            anchorId: model.selectedGarment!.id,
            secondGarmentId: garments[1].id
        )
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 200, body: successBody)
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertTrue(await model.buildDemoOutfit(intent: .firstBuild))
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/alternatives") == true {
                return .transportError(URLError(.notConnectedToInternet))
            }
            return .http(status: 500, body: Data())
        }
        await model.alternatives(for: .bottom)
        XCTAssertFalse(model.deviceAccessRejected)
        XCTAssertEqual(model.swapSheetDetail, "Couldn’t rank swaps. Try again.")
        XCTAssertTrue(
            model.swapAlternatives.contains { $0.reason == "Stub fallback — engine unreachable" }
        )
    }

    func testEngineBypassVoiceOverActionsFollowSuppressFlag() {
        XCTAssertFalse(
            OutfitBoardAccessibilityPolicy.exposesEngineBypassVoiceOverActions(suppressEngineActions: true)
        )
        XCTAssertTrue(
            OutfitBoardAccessibilityPolicy.exposesEngineBypassVoiceOverActions(suppressEngineActions: false)
        )
    }

    @MainActor
    func testOutfitEngineActionsDisabledWhileRejectedAndReenabledAfterClear() async throws {
        let model = try await makeModelForDeviceAccessTests()
        XCTAssertFalse(model.outfitEngineActionsDisabled)
        model.markDeviceAccessRejected()
        XCTAssertTrue(model.outfitEngineActionsDisabled)
        model.clearDeviceAccessRejected()
        XCTAssertFalse(model.outfitEngineActionsDisabled)
    }

    @MainActor
    func testFlagClearsOnSuccessfulGenerateAndSwap() async throws {
        let model = try await makeModelForDeviceAccessTests()
        model.markDeviceAccessRejected()
        let garments = try DeviceAccessTestFixtures.readyGarments()
        let anchorId = model.selectedGarment!.id
        let bottomId = garments[1].id
        let successBody = try generateSuccessBody(anchorId: anchorId, secondGarmentId: bottomId)
        let altBody = Data(
            #"{"slot":"BOTTOM","alternatives":[{"garmentId":"\#(bottomId.uuidString.lowercased())","reason":"ok","score":1}]}"#
                .utf8
        )
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 200, body: successBody)
            }
            if request.url?.path.hasSuffix("/v1/outfit/alternatives") == true {
                return .http(status: 200, body: altBody)
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertTrue(await model.buildDemoOutfit(intent: .firstBuild))
        XCTAssertFalse(model.deviceAccessRejected)
        model.markDeviceAccessRejected()
        await model.alternatives(for: .bottom)
        XCTAssertFalse(model.deviceAccessRejected)
    }

    @MainActor
    func test401OnChangeAnchorRestoresPriorOutfit() async throws {
        let model = try await makeModelForDeviceAccessTests()
        let garments = try DeviceAccessTestFixtures.readyGarments()
        let successBody = try generateSuccessBody(anchorId: garments[0].id)
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 200, body: successBody)
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertTrue(await model.buildDemoOutfit(intent: .firstBuild))
        let prior = try XCTUnwrap(model.outfit)
        let next = garments[1]
        installRemoteEngineStub { request in
            if request.url?.path.hasSuffix("/v1/outfit/generate") == true {
                return .http(status: 401, body: Data())
            }
            return .http(status: 500, body: Data())
        }
        XCTAssertFalse(await model.changeAnchor(to: next, priorOutfit: prior))
        XCTAssertTrue(model.deviceAccessRejected)
        XCTAssertEqual(model.outfit?.id, prior.id)
        XCTAssertNotEqual(model.generateFailureMessage, "Couldn’t change starting item")
    }

    @MainActor
    private func makeModelForDeviceAccessTests() async throws -> LoopDemoModel {
        DeviceTokenStore.useTestMemory()
        _ = DeviceTokenStore.save(DeviceAccessTestFixtures.validIssuedToken)
        let garments = try DeviceAccessTestFixtures.readyGarments()
        let store = InMemoryPersistenceStore(garments: garments, sets: [], defaults: .standard)
        let model = LoopDemoModel(store: store, preferences: .standard)
        await model.load()
        model.confirmProfileForDemoIfNeeded()
        model.select(garments[0])
        return model
    }

    private func installRemoteEngineStub(
        handler: @escaping (URLRequest) -> RecordingURLProtocol.StubResult
    ) {
        RecordingURLProtocol.install(handler: handler)
        OutfitEngineClient.urlSession = EngineURLSessionStub.makeSession()
        OutfitEngineClient.baseURLOverride = URL(string: "https://engine.test")!
    }

    private func generateSuccessBody(anchorId: UUID, secondGarmentId: UUID? = nil) throws -> Data {
        let gid = anchorId.uuidString.lowercased()
        let outfitId = UUID().uuidString.lowercased()
        var assignments =
            #"{"slot":"TOP","garmentId":"\#(gid)","isAnchor":true}"#
        if let secondGarmentId {
            let bottom = secondGarmentId.uuidString.lowercased()
            assignments += #",{"slot":"BOTTOM","garmentId":"\#(bottom)","isAnchor":false}"#
        }
        return try XCTUnwrap(
            Data(
                """
                {"outfitId":"\(outfitId)","assignments":[\(assignments)]}
                """.utf8
            )
        )
    }
}

enum DeviceAccessTestFixtures {
    static let secret43 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopq"
    static let validIssuedToken = "00000000-0000-4000-8000-000000000001.\(secret43)"
    static let validIssuedTokenWithURLChars =
        "00000000-0000-4000-8000-000000000002.ABCDEFGHIJKLMNOPQRSTUVWXYZabc-_defghijklmnop"

    static func readyGarments() throws -> [StubGarment] {
        let ready = FixtureWardrobeLoader.loadGarments().filter(\.isReady)
        guard ready.count >= 2 else {
            throw NSError(domain: "DeviceAccessTestFixtures", code: 1)
        }
        return Array(ready.prefix(8))
    }
}
