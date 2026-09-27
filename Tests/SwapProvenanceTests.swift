import XCTest
@testable import PersonalStylist

final class SwapProvenanceTests: XCTestCase {
    func testSwapProvenanceRoundTripsSeparatelyFromOutfitOrigin() throws {
        var metadata = OutfitGenerationMetadata(modelId: "deterministic-v0", promptVersion: "none", fallbackLevel: "DETERMINISTIC")
        metadata.lastSwap = SwapSelectionMetadata(modelId: "typesafe/jev-1.13", promptVersion: "outfit-choice-v1", fallbackLevel: "NONE", fallbackReason: nil, costUSD: 0.00001, selectedSuggestedOption: true)
        let decoded = try XCTUnwrap(OutfitGenerationEnvelope.decode(OutfitGenerationEnvelope.encode(metadata)))
        XCTAssertEqual(decoded, metadata)
        XCTAssertEqual(decoded.modelId, "deterministic-v0")
        XCTAssertEqual(decoded.lastSwap?.modelId, "typesafe/jev-1.13")
    }

    func testAlternativeDecoderKeepsTypedSelectionMetadata() throws {
        let json = """
        {"slot":"TOP","alternatives":[],"generation":{"modelId":"typesafe/jev-1.13","promptVersion":"outfit-choice-v1","fallbackLevel":"NONE","latencyMs":4}}
        """
        let response = try JSONDecoder().decode(OutfitEngineClient.AlternativesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.generation?.modelId, "typesafe/jev-1.13")
        XCTAssertEqual(response.generation?.promptVersion, "outfit-choice-v1")
    }
}
