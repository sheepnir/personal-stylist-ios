import Foundation

enum FixtureWardrobeLoader {
    private static let cacheLock = NSRecursiveLock()
    /// Disk reads for garments.json. Stays at 1 after the first payload build (#161).
    static var garmentJSONDiskReads = 0
    static var setJSONDiskReads = 0

    private static var cachedGarments: [StubGarment]?
    private static var cachedSets: [StubSet]?
    private static var cachedGarmentJSON: [[String: Any]]?
    private static var cachedSetJSON: [[String: Any]]?
    private static var didLoadGarmentJSON = false
    private static var didLoadSetJSON = false

    /// Loads synthetic wardrobe from bundled `wardrobe/garments.json` (FIXTURE imagery only).
    static func loadGarments() -> [StubGarment] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedGarments { return cachedGarments }
        guard let data = loadData(resource: "garments") else {
            cachedGarments = []
            return []
        }
        let decoded = (try? decodeGarments(data)) ?? []
        cachedGarments = decoded
        return decoded
    }

    static func loadSets() -> [StubSet] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedSets { return cachedSets }
        guard let data = loadData(resource: "sets") else {
            cachedSets = []
            return []
        }
        let decoded = (try? JSONDecoder().decode([FixtureSetDTO].self, from: data).compactMap { $0.asStub() }) ?? []
        cachedSets = decoded
        return decoded
    }

    /// Full fixture rows used as overlays for bundled ids (live store is request SoT).
    static func loadGarmentJSONObjects() -> [[String: Any]] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if didLoadGarmentJSON { return cachedGarmentJSON ?? [] }
        didLoadGarmentJSON = true
        garmentJSONDiskReads += 1
        guard let data = loadData(resource: "garments"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            cachedGarmentJSON = []
            return []
        }
        cachedGarmentJSON = rows
        return rows
    }

    static func loadSetJSONObjects() -> [[String: Any]] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if didLoadSetJSON { return cachedSetJSON ?? [] }
        didLoadSetJSON = true
        setJSONDiskReads += 1
        guard let data = loadData(resource: "sets"),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            cachedSetJSON = []
            return []
        }
        cachedSetJSON = rows
        return rows
    }

    static func decodeGarments(_ data: Data) throws -> [StubGarment] {
        let decoder = JSONDecoder()
        let rows = try decoder.decode([FixtureGarmentDTO].self, from: data)
        return rows.compactMap { $0.asStub() }
    }

    private static func loadData(resource: String) -> Data? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "wardrobe"),
            Bundle.main.url(forResource: resource, withExtension: "json"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else { return nil }
        return try? Data(contentsOf: url)
    }
}

private struct FixtureGarmentDTO: Decodable {
    var id: String
    var displayName: String
    var slot: String
    var readiness: String
    var availability: String
    var colorPrimary: StubColorPrimary?
    var pattern: String?
    var surface: String?
    var imagePath: String?
    var formality: Int?
    var warmth: Int?
    var setId: String?
    var keepTogether: Bool?
    var lastWornOn: String?
    var daysSinceIntake: Int?

    func asStub() -> StubGarment? {
        guard let uuid = UUID(uuidString: id),
              let slot = StubSlot(rawValue: slot),
              let readiness = StubReadiness(rawValue: readiness) else { return nil }
        return StubGarment(
            id: uuid,
            displayName: displayName,
            slot: slot,
            readiness: readiness,
            availability: availability,
            colorPrimary: colorPrimary,
            pattern: pattern,
            surface: surface,
            imagePath: imagePath,
            formality: formality,
            warmth: warmth,
            setId: setId.flatMap(UUID.init(uuidString:)),
            keepTogether: keepTogether,
            lastWornOn: lastWornOn,
            daysSinceIntake: daysSinceIntake
        )
    }
}

private struct FixtureSetDTO: Decodable {
    var id: String
    var displayName: String
    var keepTogether: Bool
    var memberGarmentIds: [String]
    var notes: String?

    func asStub() -> StubSet? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let members = memberGarmentIds.compactMap(UUID.init(uuidString:))
        return StubSet(
            id: uuid,
            displayName: displayName,
            keepTogether: keepTogether,
            memberGarmentIds: members,
            notes: notes
        )
    }
}
