import Foundation

/// Loads the primary user's profile seed (a synthetic sample persona) from bundled JSON (PRD §7.1 / M1-F01-07).
/// Persona-specific literals live only in seed/fixture files (AC-6).
enum FounderProfileSeedLoader {
    static func loadDraft() -> StubStyleProfile? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "founder-seed", withExtension: "json", subdirectory: "profile"),
            Bundle.main.url(forResource: "founder-seed", withExtension: "json"),
        ]
        guard let url = candidates.compactMap({ $0 }).first,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> StubStyleProfile {
        let dto = try JSONDecoder().decode(SeedDTO.self, from: data)
        guard let id = UUID(uuidString: dto.id) else {
            throw DecodeError.badId
        }
        return StubStyleProfile(
            id: id,
            age: dto.age,
            profession: dto.profession,
            workEnvironment: dto.workEnvironment,
            workEnvironmentLabel: dto.workEnvironmentLabel,
            typicalWeekNotes: dto.typicalWeekNotes,
            goals: dto.goals ?? [],
            constraintsNotes: dto.constraintsNotes,
            experimentationLevel: dto.experimentationLevel,
            summary: dto.summary,
            summaryUserOwned: false,
            version: dto.version ?? 1,
            confirmedAt: nil,
            seedSource: dto.seedSource ?? "founder-seed.json"
        )
    }

    enum DecodeError: Error { case badId }
}

private struct SeedDTO: Decodable {
    var id: String
    var age: Int?
    var profession: String?
    var workEnvironment: String?
    var workEnvironmentLabel: String?
    var typicalWeekNotes: String?
    var goals: [String]?
    var constraintsNotes: String?
    var experimentationLevel: Int?
    var summary: String?
    var version: Int?
    var seedSource: String?
}
