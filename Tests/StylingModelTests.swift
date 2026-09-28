import XCTest
@testable import PersonalStylist

final class StylingModelTests: XCTestCase {
    func testConsentCannotCrossModelBoundaryAndWithdrawalRemovesHeader() {
        let name = "StylingModelTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        defaults.set(StylingConsent.policyVersion, forKey: StylingConsent.defaultsKey)
        StylingModel.applyHeaders(to: &request, defaults: defaults)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Styling-Model"), StylingModel.jev.rawValue)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Styling-Policy"), StylingConsent.policyVersion)
        defaults.set(StylingModel.luna.rawValue, forKey: StylingModel.defaultsKey)
        StylingModel.applyHeaders(to: &request, defaults: defaults)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Styling-Model"), StylingModel.luna.rawValue)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Styling-Policy"))
        defaults.set(StylingModel.lunaPolicyVersion, forKey: StylingModel.lunaConsentKey)
        StylingModel.applyHeaders(to: &request, defaults: defaults)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Styling-Policy"), StylingModel.lunaPolicyVersion)
        defaults.removeObject(forKey: StylingModel.lunaConsentKey)
        StylingModel.applyHeaders(to: &request, defaults: defaults)
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Styling-Policy"))
    }

    func testSwapCopyUsesActualModelAndNeutralFallback() {
        var metadata = SwapSelectionMetadata(modelId: "openai/gpt-5.6-luna", promptVersion: "outfit-choice-luna-v1", fallbackLevel: "NONE", fallbackReason: nil, costUSD: nil, selectedSuggestedOption: true)
        XCTAssertEqual(StylingModel.swapNotice(metadata), "GPT-5.6 Luna chose the first suggestion. You can choose any option below.")
        metadata.modelId = "deterministic-v0"
        metadata.fallbackLevel = "DETERMINISTIC"
        metadata.fallbackReason = "INVALID_OUTPUT"
        XCTAssertFalse(StylingModel.swapNotice(metadata)!.contains("Jev"))
        XCTAssertEqual(StylingModel.swapSummary(metadata), "Updated after swap.")
    }

    func testUnknownPreferenceAndResultNeverInventAModel() {
        let name = "StylingModelTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("unapproved/model", forKey: StylingModel.defaultsKey)
        XCTAssertEqual(StylingModel.selected(in: defaults), .jev)
        XCTAssertEqual(StylingModel.resultTitle("deterministic-v0"), "Wardrobe rules")
        XCTAssertEqual(StylingModel.resultTitle("openai/gpt-5.6-luna-20260709"), "GPT-5.6 Luna")
        XCTAssertEqual(StylingModel.resultTitle("typesafe/jev-1.13-20260917"), "Jev 1.13")
    }
}
