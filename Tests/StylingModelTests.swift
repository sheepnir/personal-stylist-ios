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

final class ManualContextPreferencesTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ManualContextPreferencesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testMissingCorruptAndOldVersionDoNotRewriteStorage() throws {
        try withDefaults { defaults in
            XCTAssertNil(ManualContextPreferences.load(from: defaults))
            let corrupt = Data("broken".utf8)
            defaults.set(corrupt, forKey: ManualContextPreferences.key)
            XCTAssertNil(ManualContextPreferences.load(from: defaults))
            XCTAssertEqual(defaults.data(forKey: ManualContextPreferences.key), corrupt)
            let old = Data(#"{"version":0,"occasion":"CASUAL_DAY","temperature":"HOT","rain":true,"reviewedAt":0}"#.utf8)
            defaults.set(old, forKey: ManualContextPreferences.key)
            XCTAssertNil(ManualContextPreferences.load(from: defaults))
            XCTAssertEqual(defaults.data(forKey: ManualContextPreferences.key), old)
        }
    }

    func testUnknownEnumsFallBackIndependently() {
        withDefaults { defaults in
            defaults.set(Data(#"{"version":1,"occasion":"FUTURE_OCCASION","temperature":"HOT","rain":true,"reviewedAt":0}"#.utf8), forKey: ManualContextPreferences.key)
            let saved = ManualContextPreferences.load(from: defaults)
            XCTAssertEqual(saved?.context.occasion, .workStandard)
            XCTAssertEqual(saved?.context.temperature, .hot)
            XCTAssertEqual(saved?.context.rain, true)
            defaults.set(Data(#"{"version":1,"occasion":"CASUAL_DAY","temperature":"FUTURE_TEMP","rain":false,"reviewedAt":0}"#.utf8), forKey: ManualContextPreferences.key)
            XCTAssertEqual(ManualContextPreferences.load(from: defaults)?.context,
                           ManualOutfitContext(occasion: .casualDay, temperature: .mild, rain: false))
        }
    }

    func testLocalMidnightAndTimeZoneUseCurrentCalendarWithoutChangingChoices() throws {
        let reviewed = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T06:59:00Z"))
        let now = reviewed.addingTimeInterval(120)
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        XCTAssertTrue(ManualContextPreferences.reviewCopy(reviewedAt: reviewed, now: now, calendar: pacific).contains("Last-used"))
        XCTAssertTrue(ManualContextPreferences.reviewCopy(reviewedAt: reviewed, now: now, calendar: utc).contains("Manually selected"))
        XCTAssertTrue(ManualContextPreferences.reviewCopy(reviewedAt: nil, now: now, calendar: utc).contains("Default"))
        XCTAssertTrue(ManualContextPreferences.reviewCopy(reviewedAt: reviewed, now: now.addingTimeInterval(86400), calendar: utc).contains("Last-used"))
    }

    @MainActor
    func testChoicesSurviveModelRecreationAndSameValueConfirmation() {
        withDefaults { defaults in
            var now = Date(timeIntervalSince1970: 1_790_784_000)
            let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
            let model = LoopDemoModel(store: store, preferences: defaults, contextNow: { now })
            XCTAssertEqual(model.manualContext, ManualOutfitContext())
            XCTAssertNil(defaults.data(forKey: ManualContextPreferences.key))
            model.temperatureBand = .cold
            model.rain = true
            model.occasion = .eveningOut
            let persisted = defaults.data(forKey: ManualContextPreferences.key)
            let restored = LoopDemoModel(store: store, preferences: defaults, contextNow: { now })
            XCTAssertEqual(restored.manualContext, model.manualContext)
            XCTAssertEqual(defaults.data(forKey: ManualContextPreferences.key), persisted)
            now = now.addingTimeInterval(86400)
            XCTAssertTrue(restored.contextReviewCopy.contains("Last-used"))
            restored.confirmManualContext()
            XCTAssertEqual(restored.contextReviewedAt, now)
            XCTAssertEqual(restored.manualContext, model.manualContext)
            XCTAssertFalse(restored.contextReviewCopy.contains("Last-used"))
            XCTAssertFalse(restored.isGenerating)
        }
    }
}
