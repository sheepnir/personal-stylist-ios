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
}
