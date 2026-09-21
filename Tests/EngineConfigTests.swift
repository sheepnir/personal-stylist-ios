import XCTest
@testable import PersonalStylist

/// Regression coverage for #180 — Release builds must not honor launch-arg / env
/// engine URL overrides; DEBUG builds must keep the Simulator demo override path.
final class EngineConfigTests: XCTestCase {
    func testDebugBuildCompilesInLaunchArgAndEnvOverrides() {
        #if DEBUG
        XCTAssertTrue(
            EngineConfig.allowsLaunchArgAndEnvOverride,
            "DEBUG builds must allow -outfitEngineBaseURL / OUTFIT_ENGINE_BASE_URL for Simulator demos"
        )
        #else
        XCTAssertFalse(
            EngineConfig.allowsLaunchArgAndEnvOverride,
            "Release builds must compile out launch-arg / env engine URL overrides (#180)"
        )
        #endif
    }

    func testLaunchArgOverrideWinsOverEnv() {
        let url = EngineConfig.launchArgOrEnvOverride(
            arguments: ["xctest", "-outfitEngineBaseURL", "http://127.0.0.1:8787"],
            environment: ["OUTFIT_ENGINE_BASE_URL": "https://evil.example"]
        )
        XCTAssertEqual(url, "http://127.0.0.1:8787")
    }

    func testEnvOverrideWhenNoLaunchArg() {
        let url = EngineConfig.launchArgOrEnvOverride(
            arguments: ["xctest"],
            environment: ["OUTFIT_ENGINE_BASE_URL": "https://stylist-backend.example.invalid"]
        )
        XCTAssertEqual(url, "https://stylist-backend.example.invalid")
    }

    func testEmptyLaunchArgFallsThroughToEnv() {
        let url = EngineConfig.launchArgOrEnvOverride(
            arguments: ["xctest", "-outfitEngineBaseURL", "   "],
            environment: ["OUTFIT_ENGINE_BASE_URL": "http://127.0.0.1:8787"]
        )
        XCTAssertEqual(url, "http://127.0.0.1:8787")
    }

    func testMissingOverridesReturnNil() {
        XCTAssertNil(
            EngineConfig.launchArgOrEnvOverride(arguments: ["xctest"], environment: [:])
        )
    }

    func testPublicHTTPSDefaultIsHTTPS() {
        let url = URL(string: EngineConfig.defaultPublicHTTPSBase)!
        XCTAssertEqual(url.scheme?.lowercased(), "https")
        XCTAssertEqual(url.host, "stylist-backend.example.invalid")
    }
    /// A fresh Debug checkout ships an empty Info.plist engine URL, so the Simulator must fall
    /// through to the local bridge. Skipped when a developer supplied LocalSecrets.xcconfig / env.
    func testSimulatorFallsBackToLocalBridgeWhenNoURLConfigured() throws {
        #if targetEnvironment(simulator)
        let plist = (Bundle.main.object(forInfoDictionaryKey: "OUTFIT_ENGINE_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let override = EngineConfig.launchArgOrEnvOverride(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
        try XCTSkipUnless(plist.isEmpty && override == nil, "engine URL configured locally")
        XCTAssertEqual(EngineConfig.baseURL.absoluteString, EngineConfig.defaultLocalBase)
        XCTAssertFalse(EngineConfig.isRemoteHTTPS)
        #else
        throw XCTSkip("simulator-only")
        #endif
    }
}
