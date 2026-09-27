import XCTest
import SwiftData
@testable import PersonalStylist

/// #44 (iOS-A1) — decode `promptVersion` / `fallbackReason` and store them with the outfit in
/// `OutfitEntity.generationJSON` (versioned envelope, no schema change). Fixtures are labeled
/// ADR-0001 §10.5 fixtures; no provider is contacted.
final class OutfitGenerationMetadataTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "OutfitGenerationMetadataTests.\(UUID().uuidString)"
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

    private static let fullMetadata = OutfitGenerationMetadata(
        modelId: "mock/stylist-v0",
        promptVersion: "outfit-t2-d1",
        fallbackLevel: "DETERMINISTIC",
        fallbackReason: "SPEND_CAP",
        spendState: "HARD_CAP_DETERMINISTIC",
        candidateSetHash: "abc123",
        latencyMs: 12,
        repairAttempts: 0,
        costUSD: 0
    )

    // MARK: - Envelope

    func testEnvelopeRoundTripsEveryField() throws {
        let data = try XCTUnwrap(OutfitGenerationEnvelope.encode(Self.fullMetadata))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(OutfitGenerationEnvelope.decode(data), Self.fullMetadata)
    }

    func testEnvelopeHoldsMetadataOnly() throws {
        let data = try XCTUnwrap(OutfitGenerationEnvelope.encode(Self.fullMetadata))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "generation"])
        let generation = try XCTUnwrap(object["generation"] as? [String: Any])
        XCTAssertTrue(Set(generation.keys).isSubset(of: [
            "modelId", "promptVersion", "fallbackLevel", "fallbackReason", "spendState",
            "candidateSetHash", "latencyMs", "repairAttempts", "costUSD",
        ]))
    }

    func testLegacyNilBlobMeansNoMetadata() {
        XCTAssertNil(OutfitGenerationEnvelope.encode(nil))
        XCTAssertNil(OutfitGenerationEnvelope.decode(nil))
    }

    func testUnknownSchemaVersionMeansNoMetadata() {
        let future = Data(#"{"schemaVersion":2,"generation":{"fallbackReason":"PROVIDER_ERROR"}}"#.utf8)
        XCTAssertNil(OutfitGenerationEnvelope.decode(future))
        let missing = Data(#"{"generation":{"fallbackReason":"PROVIDER_ERROR"}}"#.utf8)
        XCTAssertNil(OutfitGenerationEnvelope.decode(missing))
    }

    func testUnreadableBlobMeansNoMetadata() {
        XCTAssertNil(OutfitGenerationEnvelope.decode(Data("not json".utf8)))
        XCTAssertNil(OutfitGenerationEnvelope.decode(Data()))
    }

    func testEnvelopeIgnoresUnknownKeys() {
        let data = Data(#"{"schemaVersion":1,"extra":true,"generation":{"promptVersion":"none","newField":7}}"#.utf8)
        XCTAssertEqual(OutfitGenerationEnvelope.decode(data), OutfitGenerationMetadata(promptVersion: "none"))
    }

    func testUnknownFutureFallbackReasonSurvivesRoundTrip() {
        let metadata = OutfitGenerationMetadata(fallbackReason: "SOME_FUTURE_REASON")
        let decoded = OutfitGenerationEnvelope.decode(OutfitGenerationEnvelope.encode(metadata))
        XCTAssertEqual(decoded?.fallbackReason, "SOME_FUTURE_REASON")
    }

    // MARK: - Response decoding (labeled ADR-0001 §10.5 fixtures)

    private func decodeResponse(generationJSON: String?) throws -> OutfitEngineClient.GenerateResponse {
        let body = ADR0001GenerateFixtures.generateResponse(
            assignments: [("TOP", UUID(), true)],
            generationJSON: generationJSON
        )
        return try JSONDecoder().decode(OutfitEngineClient.GenerateResponse.self, from: body)
    }

    func testDecodesPromptVersionAndEachKnownFallbackReason() throws {
        for reason in ["PROVIDER_ERROR", "INVALID_OUTPUT", "SPEND_CAP"] {
            let response = try decodeResponse(generationJSON: ADR0001GenerateFixtures.generationJSON(
                fallbackReasonJSON: "\"\(reason)\"",
                promptVersion: "outfit-t2-d1"
            ))
            XCTAssertEqual(response.generation?.fallbackReason, reason)
            XCTAssertEqual(response.generation?.promptVersion, "outfit-t2-d1")
        }
    }

    func testTodaysDeterministicResponseHasNoFallbackReason() throws {
        let response = try decodeResponse(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: nil))
        XCTAssertNil(response.generation?.fallbackReason)
        XCTAssertEqual(response.generation?.promptVersion, "none")
        XCTAssertEqual(response.generation?.fallbackLevel, "DETERMINISTIC")
    }

    func testUnknownFallbackReasonDecodesAsRawString() throws {
        let response = try decodeResponse(generationJSON: ADR0001GenerateFixtures.generationJSON(
            fallbackReasonJSON: #""SOME_FUTURE_REASON""#
        ))
        XCTAssertEqual(response.generation?.fallbackReason, "SOME_FUTURE_REASON")
    }

    func testEmptyFallbackReasonStaysPresent() throws {
        let response = try decodeResponse(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: #""""#))
        XCTAssertEqual(response.generation?.fallbackReason, "")
    }

    func testUndecodableFallbackReasonNeverFailsDecoding() throws {
        for raw in ["42", "null", "true", #"{"code":"X"}"#, #"["PROVIDER_ERROR"]"#] {
            let response = try decodeResponse(generationJSON: ADR0001GenerateFixtures.generationJSON(fallbackReasonJSON: raw))
            XCTAssertEqual(response.generation?.fallbackReason, "", "value \(raw) must decode as present-but-unknown")
        }
    }

    func testOlderResponsesStillDecode() throws {
        let noGeneration = try decodeResponse(generationJSON: nil)
        XCTAssertNil(noGeneration.generation)
        XCTAssertNil(OutfitEngineClient.mapToStubOutfit(noGeneration, anchorId: UUID()).generation)

        let sparse = try decodeResponse(generationJSON: #"{"fallbackLevel":"DETERMINISTIC"}"#)
        XCTAssertEqual(sparse.generation?.fallbackLevel, "DETERMINISTIC")
        XCTAssertNil(sparse.generation?.promptVersion)
        XCTAssertNil(sparse.generation?.fallbackReason)
    }

    func testMistypedMetadataFieldsDoNotFailDecoding() throws {
        let response = try decodeResponse(generationJSON: #"{"promptVersion":3,"latencyMs":"slow","costUSD":"free","fallbackLevel":"DETERMINISTIC"}"#)
        XCTAssertNil(response.generation?.promptVersion)
        XCTAssertNil(response.generation?.latencyMs)
        XCTAssertNil(response.generation?.costUSD)
        XCTAssertEqual(response.generation?.fallbackLevel, "DETERMINISTIC")
    }

    func testMapToStubOutfitCarriesMetadata() throws {
        let response = try decodeResponse(generationJSON: ADR0001GenerateFixtures.generationJSON(
            fallbackReasonJSON: #""INVALID_OUTPUT""#,
            promptVersion: "outfit-t2-d1"
        ))
        let outfit = OutfitEngineClient.mapToStubOutfit(response, anchorId: UUID())
        XCTAssertEqual(outfit.generation?.fallbackReason, "INVALID_OUTPUT")
        XCTAssertEqual(outfit.generation?.promptVersion, "outfit-t2-d1")
        XCTAssertEqual(outfit.generation?.modelId, "deterministic-v0")
        XCTAssertEqual(outfit.generation?.latencyMs, 12)
    }

    // MARK: - Storage in OutfitEntity.generationJSON

    private func look(generation: OutfitGenerationMetadata?) -> StubOutfit {
        StubOutfit(
            id: UUID(),
            assignments: [StubOutfitAssignment(slot: .top, garmentId: UUID(), gapReason: nil, isAnchor: true)],
            rationaleSummary: "look",
            offlineCached: false,
            generation: generation
        )
    }

    @MainActor
    func testSwiftDataStoresMetadataInGenerationJSON() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        let saved = look(generation: Self.fullMetadata)
        try await store.saveOutfit(saved)

        let fetched = await store.fetchOutfits()
        XCTAssertEqual(fetched.first?.generation, Self.fullMetadata)

        let entities = try container.mainContext.fetch(FetchDescriptor<OutfitEntity>())
        let blob = try XCTUnwrap(entities.first?.generationJSON)
        XCTAssertEqual(OutfitGenerationEnvelope.decode(blob), Self.fullMetadata)
    }

    @MainActor
    func testResaveWithoutMetadataKeepsStoredMetadata() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        var saved = look(generation: Self.fullMetadata)
        try await store.saveOutfit(saved)

        saved.generation = nil
        saved.rationaleSummary = "Updated after swap."
        try await store.saveOutfit(saved)

        let fetched = await store.fetchOutfits()
        XCTAssertEqual(fetched.first?.rationaleSummary, "Updated after swap.")
        XCTAssertEqual(fetched.first?.generation, Self.fullMetadata)
    }

    @MainActor
    func testExistingOutfitWithoutBlobHasNoMetadata() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        let legacy = look(generation: nil)
        try await store.saveOutfit(legacy)

        let entities = try container.mainContext.fetch(FetchDescriptor<OutfitEntity>())
        XCTAssertNil(entities.first?.generationJSON)
        let fetched = await store.fetchOutfits()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched.first?.generation)
    }

    @MainActor
    func testUnknownSchemaVersionBlobLoadsAsNoMetadata() async throws {
        let container = try TestModelContainers.makeInMemory()
        let store = SwiftDataPersistenceStore(container: container, defaults: defaults)
        let saved = look(generation: nil)
        try await store.saveOutfit(saved)
        let entities = try container.mainContext.fetch(FetchDescriptor<OutfitEntity>())
        entities.first?.generationJSON = Data(#"{"schemaVersion":99,"generation":{}}"#.utf8)
        try container.mainContext.save()

        let fetched = await store.fetchOutfits()
        XCTAssertEqual(fetched.first?.id, saved.id)
        XCTAssertNil(fetched.first?.generation)
    }

    func testInMemoryStoreKeepsMetadataOnResave() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var saved = look(generation: Self.fullMetadata)
        try await store.saveOutfit(saved)
        saved.generation = nil
        try await store.saveOutfit(saved)
        let fetched = await store.fetchOutfits()
        XCTAssertEqual(fetched.first?.generation, Self.fullMetadata)
    }

    // MARK: - Generate → board (engine stubbed; no provider traffic)

    @MainActor
    func testGenerateStoresMetadataWithTheBoardOutfit() async throws {
        let (model, anchor, partner) = try await readyModel()
        let body = ADR0001GenerateFixtures.generateResponse(
            assignments: [("TOP", anchor.id, true), ("BOTTOM", partner.id, false)],
            generationJSON: ADR0001GenerateFixtures.generationJSON(
                fallbackReasonJSON: #""PROVIDER_ERROR""#,
                promptVersion: "outfit-t2-d1"
            )
        )
        EngineURLSessionStub.installClientHooks { _ in .http(status: 200, body: body) }

        let ok = await model.buildDemoOutfit(intent: .firstBuild)
        XCTAssertTrue(ok)
        XCTAssertEqual(model.outfit?.generation?.fallbackReason, "PROVIDER_ERROR")
        XCTAssertEqual(model.outfit?.generation?.promptVersion, "outfit-t2-d1")
        Self.assertOnlyEngineTraffic()
    }

    /// Phase A: the app only talks to the outfit engine; never to a provider host.
    static func assertOnlyEngineTraffic(file: StaticString = #filePath, line: UInt = #line) {
        let recorded = RecordingURLProtocol.recorded
        XCTAssertFalse(recorded.isEmpty, file: file, line: line)
        for request in recorded {
            XCTAssertTrue(
                request.path.hasPrefix("/v1/outfit/") || request.path == "/health",
                "unexpected request path \(request.path)", file: file, line: line
            )
            XCTAssertFalse(request.url.host?.contains("openrouter") ?? false, file: file, line: line)
        }
    }

    @MainActor
    private func readyModel() async throws -> (LoopDemoModel, StubGarment, StubGarment) {
        let ready = FixtureWardrobeLoader.loadGarments().filter { $0.isReady && $0.availability == "AVAILABLE" }
        let anchor = try XCTUnwrap(ready.first { $0.slot == .top })
        let partner = try XCTUnwrap(ready.first { $0.slot == .bottom })
        let store = InMemoryPersistenceStore(garments: ready, sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.confirmProfileForDemoIfNeeded()
        model.select(anchor)
        return (model, anchor, partner)
    }
}
