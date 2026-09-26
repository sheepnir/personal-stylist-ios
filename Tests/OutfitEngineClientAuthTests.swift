import XCTest
@testable import PersonalStylist

final class OutfitEngineClientAuthTests: XCTestCase {
    func testOnlyLoopbackHTTPMayOmitDeviceToken() throws {
        XCTAssertFalse(try OutfitEngineClient.requiresDeviceToken(for: URL(string: "http://127.0.0.1:8787")!))
        XCTAssertTrue(try OutfitEngineClient.requiresDeviceToken(for: URL(string: "https://example.test")!))
        XCTAssertThrowsError(try OutfitEngineClient.requiresDeviceToken(for: URL(string: "http://example.test")!))
    }

    func testRemoteHTTPSGenerateFailClosesWithoutDeviceToken() async {
        // Clear any Keychain residue from prior tests / Debug seeds.
        _ = DeviceTokenStore.clear()
        XCTAssertFalse(DeviceTokenStore.hasToken)

        // Fail-closed applies to remote HTTPS engines only. A clean Debug Simulator build resolves
        // to the local bridge (empty Info.plist URL), so this test returns early there; the
        // generate call below runs only when LocalSecrets.xcconfig or an override supplies HTTPS.
        guard EngineConfig.isRemoteHTTPS else {
            // Local bridge demo builds skip this assertion — fail-closed applies to remote only.
            return
        }

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
        } catch OutfitEngineClient.ClientError.anchorNotInWardrobe {
            XCTFail("should fail closed on auth before wardrobe checks when token missing")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGenerateMaps401ToUnauthorized() async throws {
        EngineURLSessionStub.tearDownClientHooks()
        DeviceTokenStore.useTestMemory()
        _ = DeviceTokenStore.save(DeviceAccessTestFixtures.validIssuedToken)
        OutfitEngineClient.baseURLOverride = URL(string: "https://engine.test")!
        OutfitEngineClient.urlSession = EngineURLSessionStub.makeSession()
        RecordingURLProtocol.install { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/v1/outfit/generate") == true)
            return .http(status: 401, body: Data(#"{"title":"Unauthorized","status":401}"#.utf8))
        }
        let garments = try DeviceAccessTestFixtures.readyGarments()
        do {
            _ = try await OutfitEngineClient.generate(
                garments: garments,
                sets: [],
                anchorId: garments[0].id,
                flight: OutfitEngineClient.EngineDataTask()
            )
            XCTFail("expected unauthorized")
        } catch OutfitEngineClient.ClientError.unauthorized {
            // expected
        } catch {
            XCTFail("unexpected: \(error)")
        }
        RecordingURLProtocol.reset()
        OutfitEngineClient.resetTestHooks()
        DeviceTokenStore.resetTestHooks()
    }

    func testAlternativesMaps401ToUnauthorized() async throws {
        EngineURLSessionStub.tearDownClientHooks()
        DeviceTokenStore.useTestMemory()
        _ = DeviceTokenStore.save(DeviceAccessTestFixtures.validIssuedToken)
        OutfitEngineClient.baseURLOverride = URL(string: "https://engine.test")!
        OutfitEngineClient.urlSession = EngineURLSessionStub.makeSession()
        RecordingURLProtocol.install { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/v1/outfit/alternatives") == true)
            return .http(status: 401, body: Data())
        }
        let garments = try DeviceAccessTestFixtures.readyGarments()
        let outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: garments[0].id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "test",
            offlineCached: false
        )
        do {
            _ = try await OutfitEngineClient.fetchAlternatives(
                slot: .top,
                outfit: outfit,
                garments: garments,
                sets: []
            )
            XCTFail("expected unauthorized")
        } catch OutfitEngineClient.ClientError.unauthorized {
            // expected
        } catch {
            XCTFail("unexpected: \(error)")
        }
        RecordingURLProtocol.reset()
        OutfitEngineClient.resetTestHooks()
        DeviceTokenStore.resetTestHooks()
    }
}
