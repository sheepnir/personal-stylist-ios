import Foundation

/// #44 (iOS-A1) — how an outfit was generated, stored with the outfit.
/// Metadata only: no garment names, rationale, or ids (ADR-0001 §8, §10.2).
/// `promptVersion` is diagnostics only and never reaches the board.
struct OutfitGenerationMetadata: Codable, Hashable, Sendable {
    var modelId: String?
    var promptVersion: String?
    var fallbackLevel: String?
    /// Raw engine value, kept as a String (never a closed enum). Present only when an
    /// eligible provider attempt fell back; absent means no fallback notice.
    /// A present-but-undecodable value is stored as `""` so it stays "present".
    var fallbackReason: String?
    var spendState: String?
    var candidateSetHash: String?
    var latencyMs: Int?
    var repairAttempts: Int?
    var costUSD: Double?

    init(
        modelId: String? = nil,
        promptVersion: String? = nil,
        fallbackLevel: String? = nil,
        fallbackReason: String? = nil,
        spendState: String? = nil,
        candidateSetHash: String? = nil,
        latencyMs: Int? = nil,
        repairAttempts: Int? = nil,
        costUSD: Double? = nil
    ) {
        self.modelId = modelId
        self.promptVersion = promptVersion
        self.fallbackLevel = fallbackLevel
        self.fallbackReason = fallbackReason
        self.spendState = spendState
        self.candidateSetHash = candidateSetHash
        self.latencyMs = latencyMs
        self.repairAttempts = repairAttempts
        self.costUSD = costUSD
    }
}

/// Versioned JSON envelope in `OutfitEntity.generationJSON` — no SwiftData schema change.
/// A nil blob, an unreadable blob, or an unknown `schemaVersion` all mean "no metadata".
enum OutfitGenerationEnvelope {
    static let currentSchemaVersion = 1

    private struct Header: Decodable {
        var schemaVersion: Int
    }

    private struct V1: Codable {
        var schemaVersion: Int
        var generation: OutfitGenerationMetadata
    }

    static func encode(_ metadata: OutfitGenerationMetadata?) -> Data? {
        guard let metadata else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(V1(schemaVersion: currentSchemaVersion, generation: metadata))
    }

    static func decode(_ data: Data?) -> OutfitGenerationMetadata? {
        guard let data,
              let header = try? JSONDecoder().decode(Header.self, from: data),
              header.schemaVersion == currentSchemaVersion else { return nil }
        return (try? JSONDecoder().decode(V1.self, from: data))?.generation
    }
}
