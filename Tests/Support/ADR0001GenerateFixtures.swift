import Foundation

/// LABELED FIXTURES — built from ADR-0001 §10.5 (`GenerationMeta.fallbackReason`), not captured
/// from a live engine or provider. The openapi change ships with #26 A-3; until then these are
/// the only source of `fallbackReason` in tests (#44). No provider is contacted.
enum ADR0001GenerateFixtures {
    /// `generation` object JSON for a generate response. `fallbackReasonJSON` is inserted
    /// verbatim so tests can send absent (`nil`), strings, `null`, or non-string values.
    static func generationJSON(
        fallbackReasonJSON: String?,
        promptVersion: String = "none",
        modelId: String = "deterministic-v0",
        fallbackLevel: String = "DETERMINISTIC"
    ) -> String {
        var fields = [
            #""modelId":"\#(modelId)""#,
            #""promptVersion":"\#(promptVersion)""#,
            #""latencyMs":12"#,
            #""fallbackLevel":"\#(fallbackLevel)""#,
            #""costUSD":null"#,
        ]
        if let fallbackReasonJSON {
            fields.append(#""fallbackReason":\#(fallbackReasonJSON)"#)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// Full generate response. `generationJSON == nil` models an older response with no
    /// `generation` block at all.
    static func generateResponse(
        outfitId: UUID = UUID(),
        assignments: [(slot: String, garmentId: UUID, isAnchor: Bool)],
        generationJSON: String?
    ) -> Data {
        let rows = assignments.map { a in
            #"{"slot":"\#(a.slot)","garmentId":"\#(a.garmentId.uuidString.lowercased())","isAnchor":\#(a.isAnchor)}"#
        }
        var body = #"{"outfitId":"\#(outfitId.uuidString.lowercased())","assignments":[\#(rows.joined(separator: ","))],"rationale":{"summary":"Fixture summary."}"#
        if let generationJSON {
            body += #","generation":\#(generationJSON)"#
        }
        body += "}"
        return Data(body.utf8)
    }
}
