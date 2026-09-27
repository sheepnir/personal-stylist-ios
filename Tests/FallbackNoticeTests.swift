import XCTest
@testable import PersonalStylist

/// #45 / #46 (iOS-A2 / iOS-A3) — "Built without the AI stylist" notice.
/// Spec 0001 rev 3 R9, R10, R11, R14. Engine responses are labeled ADR-0001 §10.5 fixtures
/// served by the stubbed session; no provider is contacted.
final class FallbackNoticeTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "FallbackNoticeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        EngineURLSessionStub.tearDownClientHooks()
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Copy (R10, R11, R14)

    private static let unavailable = "The AI stylist wasn't available, so the app put this one together from your wardrobe."
    private static let noUsable = "The AI stylist couldn't come up with a usable outfit this time, so the app put this one together from your wardrobe."
    private static let limitVariantB = "The AI stylist isn't available right now, so the app put this outfit together from your wardrobe."
    private static let generic = "This time the app put this outfit together from your wardrobe on its own."

    private func notice(_ reason: String?) -> FallbackNotice? {
        FallbackNoticeCopy.notice(for: OutfitGenerationMetadata(promptVersion: "outfit-t2-d1", fallbackReason: reason))
    }

    func testEachMappedReasonUsesItsExactBody() {
        XCTAssertEqual(FallbackNoticeCopy.title, "Built without the AI stylist")
        XCTAssertEqual(notice("PROVIDER_ERROR")?.body, Self.unavailable)
        XCTAssertEqual(notice("INVALID_OUTPUT")?.body, Self.noUsable)
        XCTAssertEqual(notice("SPEND_CAP")?.body, Self.limitVariantB)
    }

    func testUnknownEmptyOrUndecodableValuesGetTheGenericBody() {
        for raw in ["SOME_FUTURE_REASON", "", "provider_error", " PROVIDER_ERROR", "MODEL_NOT_ALLOWED"] {
            XCTAssertEqual(notice(raw)?.body, Self.generic, "value \(raw.debugDescription)")
            XCTAssertEqual(notice(raw)?.reason, .other)
        }
    }

    func testAbsentReasonShowsNoNotice() {
        XCTAssertNil(notice(nil))
        XCTAssertNil(FallbackNoticeCopy.notice(for: nil))
        XCTAssertNil(FallbackNoticeCopy.notice(for: OutfitGenerationMetadata(fallbackLevel: "DETERMINISTIC")))
    }

    func testSpendCapUsesVariantBOnly() {
        let body = notice("SPEND_CAP")?.body ?? ""
        XCTAssertFalse(body.contains("reset"))
        XCTAssertNil(body.range(of: #"\d"#, options: .regularExpression), "Variant A (a reset time) is out of scope")
    }

    func testVoiceOverLabelIsTitleThenBody() {
        for reason in ["PROVIDER_ERROR", "INVALID_OUTPUT", "SPEND_CAP", "SOME_FUTURE_REASON"] {
            let n = notice(reason)
            XCTAssertEqual(n?.accessibilityLabel, "Built without the AI stylist. \(n?.body ?? "")")
        }
    }

    func testNoticeNeverShowsRawValuesOrPromptVersion() {
        for reason in ["PROVIDER_ERROR", "INVALID_OUTPUT", "SPEND_CAP", "SOME_FUTURE_REASON", ""] {
            let n = notice(reason)
            for text in [n?.title ?? "", n?.body ?? "", n?.accessibilityLabel ?? ""] {
                XCTAssertFalse(text.contains("_"), text)
                XCTAssertFalse(text.contains("outfit-t2-d1"), text)
                if !reason.isEmpty { XCTAssertFalse(text.contains(reason), text) }
                for word in ["fallback", "provider", "deterministic", "model", "engine", "HTTP"] {
                    XCTAssertNil(text.range(of: word, options: .caseInsensitive), "\(word) in \(text)")
                }
            }
        }
    }

    // MARK: - Board lifecycle (R9, §2.5)

    @MainActor
    func testNoticePresentOrAbsentForEachReasonAfterGenerate() async throws {
        let cases: [(String?, FallbackNoticeCopy.Reason?)] = [
            (#""PROVIDER_ERROR""#, .providerError),
            (#""INVALID_OUTPUT""#, .invalidOutput),
            (#""SPEND_CAP""#, .spendCap),
            (#""SOME_FUTURE_REASON""#, .other),
            (#""""#, .other),
            ("42", .other),
            ("null", nil),
            (nil, nil),
        ]
        for (raw, expected) in cases {
            let h = try await Harness.make(defaults: defaults)
            h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: raw))
            let ok = await h.model.buildDemoOutfit(intent: .firstBuild)
            XCTAssertTrue(ok)
            XCTAssertEqual(h.model.boardFallbackNotice?.reason, expected, "fallbackReason \(raw ?? "absent")")
            XCTAssertEqual(h.announced.count, expected == nil ? 0 : 1)
            EngineURLSessionStub.tearDownClientHooks()
        }
    }

    @MainActor
    func testDeterministicResultWithoutReasonRendersNormally() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: nil, fallbackLevel: "DETERMINISTIC"))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertNotNil(h.model.outfit)
        XCTAssertNil(h.model.boardFallbackNotice)
    }

    @MainActor
    func testPresenceIsTheKeyEvenWhenFallbackLevelIsNotDeterministic() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(
            fallbackReasonJSON: #""PROVIDER_ERROR""#,
            fallbackLevel: "NONE"
        ))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .providerError)
    }

    @MainActor
    func testSwapUndoAndKeepKeepTheNotice() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""INVALID_OUTPUT""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .invalidOutput)

        let other = try XCTUnwrap(h.spareBottom)
        h.model.swapSlot = .bottom
        h.model.applySwap(StubSwapAlternative(id: other.id, garment: other, reason: "test", score: nil, setPartnerIds: []))
        XCTAssertEqual(h.model.outfit?.assignments.first { $0.slot == .bottom }?.garmentId, other.id)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .invalidOutput, "swap keeps")

        h.model.performSwapUndo()
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .invalidOutput, "undo swap keeps")

        h.model.setAssignmentLocked(slot: .bottom, locked: true)
        h.model.setAssignmentLocked(slot: .bottom, locked: false)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .invalidOutput, "Keep / Unlock keeps")
        XCTAssertEqual(h.announced.count, 1, "no announcement on swap, undo, or lock")
    }

    @MainActor
    func testSwapAttributionClearsForLocalChoiceAndUndoRestoresPriorExplanation() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: nil))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        let originalSummary = h.model.outfit?.rationaleSummary
        let originalGeneration = h.model.outfit?.generation
        let other = try XCTUnwrap(h.spareBottom)
        let jev = SwapSelectionMetadata(modelId: "typesafe/jev-1.13", promptVersion: "outfit-choice-v1", fallbackLevel: "NONE", fallbackReason: nil, costUSD: 0.00001, selectedSuggestedOption: true)
        h.model.swapSlot = .bottom
        h.model.applySwap(StubSwapAlternative(id: other.id, garment: other, reason: "test", score: nil, setPartnerIds: [], selectionMetadata: jev))
        XCTAssertEqual(h.model.outfit?.generation?.lastSwap, jev)
        XCTAssertEqual(h.model.outfit?.rationaleSummary, "Updated with Jev’s suggested swap.")
        h.model.performSwapUndo()
        XCTAssertEqual(h.model.outfit?.rationaleSummary, originalSummary)
        XCTAssertEqual(h.model.outfit?.generation, originalGeneration)

        h.model.applySwap(StubSwapAlternative(id: other.id, garment: other, reason: "test", score: nil, setPartnerIds: [], selectionMetadata: jev))
        defaults.removeObject(forKey: StylingConsent.defaultsKey)
        XCTAssertNil(StylingConsent.acceptedVersion(in: defaults))
        h.model.setAssignmentLocked(slot: .bottom, locked: false)
        h.model.applySwap(StubSwapAlternative(id: h.bottom.id, garment: h.bottom, reason: "local", score: nil, setPartnerIds: []))
        XCTAssertNil(h.model.outfit?.generation?.lastSwap)
        XCTAssertEqual(h.model.outfit?.rationaleSummary, "Updated after swap.")
        h.model.performSwapUndo()
        XCTAssertEqual(h.model.outfit?.generation?.lastSwap, jev)
        XCTAssertEqual(h.model.outfit?.rationaleSummary, "Updated with Jev’s suggested swap.")
    }

    @MainActor
    func testTryAnotherReplacesTheNoticeWithTheNewResultsState() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""PROVIDER_ERROR""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertNotNil(h.model.boardFallbackNotice)

        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: nil), bottom: h.spareBottom)
        let ok = await h.model.tryAnotherOutfit()
        XCTAssertTrue(ok)
        XCTAssertNil(h.model.noAlternativeReason)
        XCTAssertNil(h.model.boardFallbackNotice, "replaced by the new result's (absent) state")

        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""SPEND_CAP""#), bottom: h.bottom)
        h.model.resetShownOutfitExclusions()
        _ = await h.model.tryAnotherOutfit()
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .spendCap)
        XCTAssertEqual(h.announced.count, 2)
    }

    @MainActor
    func testNoAlternativeRestoreKeepsThePreviousOutfitsState() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""SPEND_CAP""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        let before = h.model.outfit?.id

        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: nil), noAlternativeReason: "ALL_EXCLUDED")
        _ = await h.model.tryAnotherOutfit()
        XCTAssertNotNil(h.model.noAlternativeReason)
        XCTAssertEqual(h.model.outfit?.id, before)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .spendCap)
        XCTAssertEqual(h.announced.count, 1, "restore is not a new result")
    }

    @MainActor
    func testSkeletonHidesTheNoticeAndCancelRestoresItSilently() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""PROVIDER_ERROR""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertNotNil(h.model.boardFallbackNotice)

        EngineURLSessionStub.installClientHooks { _ in .hang }
        let task = Task { await h.model.tryAnotherOutfit() }
        for _ in 0..<200 where !h.model.isGenerating {
            await Task.yield()
        }
        XCTAssertTrue(h.model.isGenerating)
        XCTAssertNil(h.model.boardFallbackNotice, "hidden behind the skeleton")

        h.model.cancelGeneration()
        RecordingURLProtocol.finishHang()
        _ = await task.value
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .providerError)
        XCTAssertEqual(h.announced.count, 1, "no announcement on cancel")
    }

    @MainActor
    func testFailureRestoresThePriorOutfitsNoticeSilently() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""INVALID_OUTPUT""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)

        EngineURLSessionStub.installClientHooks { _ in .transportError(URLError(.notConnectedToInternet)) }
        let ok = await h.model.tryAnotherOutfit()
        XCTAssertFalse(ok)
        XCTAssertNotNil(h.model.generateFailureMessage)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .invalidOutput)
        XCTAssertEqual(h.announced.count, 1)
    }

    @MainActor
    func testOfflineCachedOutfitShowsTheStoredNotice() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""SPEND_CAP""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)

        h.model.isOffline = true
        let ok = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertTrue(ok)
        XCTAssertEqual(h.model.outfit?.offlineCached, true)
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .spendCap)
        XCTAssertEqual(h.announced.count, 1)
    }

    @MainActor
    func testWearKeepsTheNoticeOnTheBoardAndPersistsTheReason() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""PROVIDER_ERROR""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)

        await h.model.confirmWear()
        XCTAssertEqual(h.model.boardFallbackNotice?.reason, .providerError)
        let stored = await h.store.fetchOutfits()
        XCTAssertEqual(stored.first?.generation?.fallbackReason, "PROVIDER_ERROR")
    }

    @MainActor
    func testClearingTheWardrobeRemovesTheNoticeWithTheOutfit() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""PROVIDER_ERROR""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        await h.model.clearWardrobeAndLooks()
        XCTAssertNil(h.model.outfit)
        XCTAssertNil(h.model.boardFallbackNotice)
    }

    @MainActor
    func testSpendCapMakesNoUsageRequest() async throws {
        let h = try await Harness.make(defaults: defaults)
        h.serve(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""SPEND_CAP""#))
        _ = await h.model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertEqual(h.model.boardFallbackNotice?.body, Self.limitVariantB)
        let paths = RecordingURLProtocol.recorded.map(\.path)
        XCTAssertEqual(paths.count, 1)
        XCTAssertFalse(paths.contains { $0.contains("usage") })
        OutfitGenerationMetadataTests.assertOnlyEngineTraffic()
    }

    // MARK: - Board only (R9)

    func testOnlyTheBoardRendersTheNotice() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let features = root.appendingPathComponent("Features")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: features, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        var users: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("boardFallbackNotice") || text.contains("FallbackNoticeCopy") {
                users.append(file.lastPathComponent)
            }
            XCTAssertFalse(text.contains("promptVersion"), "\(file.lastPathComponent) must not surface promptVersion")
        }
        XCTAssertEqual(users, ["OutfitBoardView.swift"])
    }

    // MARK: - Harness

    @MainActor
    private struct Harness {
        let model: LoopDemoModel
        let store: InMemoryPersistenceStore
        let anchor: StubGarment
        let bottom: StubGarment
        let spareBottom: StubGarment?
        let recorder: AnnouncementRecorder

        var announced: [String] { recorder.messages }

        static func make(defaults: UserDefaults) async throws -> Harness {
            let ready = FixtureWardrobeLoader.loadGarments().filter { $0.isReady && $0.availability == "AVAILABLE" }
            let anchor = try XCTUnwrap(ready.first { $0.slot == .top })
            let bottoms = ready.filter { $0.slot == .bottom }
            let bottom = try XCTUnwrap(bottoms.first)
            let store = InMemoryPersistenceStore(garments: ready, sets: [], defaults: defaults)
            let model = LoopDemoModel(store: store, preferences: defaults)
            await model.load()
            model.confirmProfileForDemoIfNeeded()
            model.select(anchor)
            let recorder = AnnouncementRecorder()
            model.postAccessibilityAnnouncement = { recorder.messages.append($0) }
            return Harness(
                model: model,
                store: store,
                anchor: anchor,
                bottom: bottom,
                spareBottom: bottoms.dropFirst().first,
                recorder: recorder
            )
        }

        /// Serve every generate with the given `generation` block (and optional bottom / no-alternative).
        func serve(generationJSON: String?, bottom chosen: StubGarment? = nil, noAlternativeReason: String? = nil) {
            let pick = chosen ?? bottom
            var body = ADR0001GenerateFixtures.generateResponse(
                assignments: [("TOP", anchor.id, true), ("BOTTOM", pick.id, false)],
                generationJSON: generationJSON
            )
            if let noAlternativeReason,
               var object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                object["noAlternativeReason"] = noAlternativeReason
                body = (try? JSONSerialization.data(withJSONObject: object)) ?? body
            }
            let response = body
            EngineURLSessionStub.installClientHooks { _ in .http(status: 200, body: response) }
        }
    }

    private final class AnnouncementRecorder {
        var messages: [String] = []
    }
}
