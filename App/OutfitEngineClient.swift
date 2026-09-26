import Foundation

/// Talks to Backend outfit engine (local bridge or public HTTPS — see `EngineConfig`).
enum OutfitEngineClient {
    static var baseURL: URL { baseURLOverride ?? EngineConfig.baseURL }
    static var generateURL: URL { baseURL.appendingPathComponent("v1/outfit/generate") }
    static var alternativesURL: URL { baseURL.appendingPathComponent("v1/outfit/alternatives") }
    static var healthURL: URL { baseURL.appendingPathComponent("health") }

    /// Test override for engine host. Production leaves this `nil` (#220).
    static var baseURLOverride: URL?

    /// Session used for generate / alternatives / health. Tests replace with a
    /// `URLProtocol`-backed ephemeral session; production keeps `URLSession.shared`.
    static var urlSession: URLSession = .shared

    /// Distinguishes "request constructed" from "handed to URL loading" (#220).
    /// `URLProtocol` only observes the latter. Production leaves this `nil`.
    enum RequestLifecyclePhase: String, Equatable {
        case constructed
        case dispatched
    }

    struct RequestLifecycleEvent: Equatable {
        var phase: RequestLifecyclePhase
        var method: String
        var path: String
        var body: Data?
    }

    static var requestLifecycleObserver: ((RequestLifecycleEvent) -> Void)?

    /// Restore production defaults after a unit test mutates hooks.
    static func resetTestHooks() {
        baseURLOverride = nil
        urlSession = .shared
        requestLifecycleObserver = nil
    }

    static func emitLifecycle(_ phase: RequestLifecyclePhase, request: URLRequest) {
        guard let observer = requestLifecycleObserver else { return }
        let url = request.url
        observer(
            RequestLifecycleEvent(
                phase: phase,
                method: request.httpMethod ?? "GET",
                path: url?.path ?? "",
                body: request.httpBody
            )
        )
    }

    /// Cancels the URLSession work started by `generate` (#162).
    final class EngineDataTask: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDataTask?
        private var cancelled = false
        private let session: URLSession

        init(session: URLSession = OutfitEngineClient.urlSession) {
            self.session = session
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let current = task
            lock.unlock()
            current?.cancel()
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try await withCheckedThrowingContinuation { continuation in
                let dataTask = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data, let response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    continuation.resume(returning: (data, response))
                }
                lock.lock()
                task = dataTask
                let shouldCancel = cancelled
                lock.unlock()
                if shouldCancel {
                    // Never resume → URLProtocol does not see loading; completion
                    // still reports URLError.cancelled so the continuation finishes.
                    dataTask.cancel()
                } else {
                    OutfitEngineClient.emitLifecycle(.dispatched, request: request)
                    dataTask.resume()
                }
            }
        }
    }

    /// PRD §11.3: request → rendered board p50 ≤ 4 s, p95 ≤ 8 s (#158).
    enum GenerationLatencyBudget {
        static let p50Milliseconds = 4_000
        static let p95Milliseconds = 8_000

        static func note(milliseconds: Int) -> String {
            if milliseconds <= p50Milliseconds {
                return "within 4 s p50 budget"
            }
            if milliseconds <= p95Milliseconds {
                return "within 8 s p95 budget"
            }
            return "over 8 s p95 budget"
        }
    }

    struct GenerationLatencySample: Identifiable, Equatable {
        var id = UUID()
        var milliseconds: Int
        /// success | failure | cancelled
        var outcome: String
        var note: String
    }

    /// Only the loopback HTTP bridge may omit credentials; remote HTTP is refused.
    static func requiresDeviceToken(for url: URL) throws -> Bool {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        if scheme == "http", ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host ?? "") {
            return false
        }
        guard scheme == "https", host != nil else { throw ClientError.badURL }
        return true
    }

    private static func applyAuth(to request: inout URLRequest) throws {
        guard let url = request.url else { throw ClientError.badURL }
        guard try requiresDeviceToken(for: url) else { return }
        guard let token = DeviceTokenStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { throw ClientError.missingDeviceToken }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    struct EngineAssignment: Decodable {
        var slot: String
        var garmentId: String?
        var gapReason: String?
        var isAnchor: Bool?
        var isLocked: Bool?
    }

    struct EngineRationale: Decodable {
        var summary: String?
        var pairingNotes: [String]?
        var teachingNote: String?
        var cautions: [String]?
    }

    struct EngineGeneration: Decodable {
        var fallbackLevel: String?
        var spendState: String?
        var modelId: String?
    }

    struct EngineCandidate: Decodable {
        var garmentId: String
        var score: Double?
        var reason: String?
    }

    struct GenerateResponse: Decodable {
        var outfitId: String
        var assignments: [EngineAssignment]
        var rationale: EngineRationale?
        var generation: EngineGeneration?
        /// D-20 / #95 — set when every different outfit was already excluded.
        var noAlternativeReason: String?
        /// Per-slot shortlist; valid until the first swap (D-33).
        var candidateSet: [String: [EngineCandidate]]?
    }


    struct AlternativeRow: Decodable {
        var garmentId: String
        var score: Double?
        var reason: String
        var setPartnerIds: [String]?
    }

    struct AlternativesResponse: Decodable {
        var slot: String
        var alternatives: [AlternativeRow]
        var emptyReason: String?
    }

    struct ProblemBody: Decodable {
        var title: String?
        var detail: String?
        var code: String?
        var status: Int?
    }

    enum ClientError: LocalizedError {
        case badURL
        case http(Int, String)
        case problem(ProblemBody)
        case decode(Error)
        case transport(Error)
        /// Starting item is READY in the UI but missing from the payload (#97).
        case anchorNotInWardrobe(UUID)
        /// Remote HTTPS generate/swap refused — no Keychain device token (#175 / D-46).
        case missingDeviceToken
        /// Device token was sent but the engine rejected it (HTTP 401 only).
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .badURL: return "Bad engine URL"
            case .http(let code, let body): return "Engine HTTP \(code): \(body.prefix(160))"
            case .problem(let p): return p.detail ?? p.title ?? p.code ?? "Engine problem"
            case .decode(let e): return "Engine decode: \(e.localizedDescription)"
            case .transport(let e): return "Engine unreachable: \(e.localizedDescription)"
            case .anchorNotInWardrobe:
                return "That starting item isn’t in the wardrobe sent to the engine. Finish details and try again."
            case .missingDeviceToken:
                return "This build has no device token for the remote stylist. Enroll a token before sending wardrobe data."
            case .unauthorized:
                return "Device access rejected (HTTP 401)"
            }
        }
    }

    /// Empty `seasons` fails Stage 1 (`passesSeason`); user-added garments have none stored.
    static let defaultSeasons = ["SPRING", "SUMMER", "FALL", "WINTER"]
    static let excludeGarmentSetsCap = 10

    // MARK: - Image-payload guard (VF-03)

    // Mirrors `backend/workers/src/validation.ts` (`IMAGE_KEY_PATTERN` /
    // `IMAGE_VALUE_PATTERN`). The Worker fails closed with 415 `IMAGE_NOT_ALLOWED`
    // when a body carries any of these, so nothing matching may ever be sent.
    // Fixture rows carry a local image reference (`imagePath`) that is client-only
    // state; the engine contract never needs it.
    //
    // The Worker's patterns use the JavaScript `i` flag, which on these ASCII-only
    // patterns folds ASCII letters and nothing else (`ſ` never matches `s`). ICU's
    // `.caseInsensitive` folds more, so inputs are ASCII-folded by hand and matched
    // against lowercase patterns instead. `scripts/check-image-guard-parity.py`
    // fails CI if the token lists below drift from the Worker's.
    private static let imageKeyPattern = try! NSRegularExpression(
        pattern: "(^|[^a-z])(image|imagedata|imagebase64|thumbnail|thumb|photo|masterimage|processedimage|pixeldata|bitmap)([^a-z]|$)"
    )
    private static let imageValuePattern = try! NSRegularExpression(
        pattern: "^data:image/|^/9j/|^ivborw0kggo"
    )
    private static let camelCaseBoundary = try! NSRegularExpression(pattern: "([a-z])([A-Z])")

    /// ECMAScript WhiteSpace + LineTerminator, i.e. what JavaScript `trimStart()`
    /// removes. U+0085 (NEL) is deliberately absent: JavaScript keeps it, so a value
    /// starting with it is not image data to the Worker either.
    private static let javaScriptWhitespace: Set<UInt32> = [
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
    ]

    /// A–Z → a–z only; every other scalar is untouched (JavaScript `i` semantics here).
    private static func foldingASCIICase(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            scalars.append((0x41...0x5A).contains(scalar.value) ? Unicode.Scalar(scalar.value + 0x20)! : scalar)
        }
        return String(scalars)
    }

    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        pattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// `imagePath` → `image_path` → matches `image`, exactly as the Worker normalises.
    static func isImageBearingKey(_ key: String) -> Bool {
        let snake = camelCaseBoundary.stringByReplacingMatches(
            in: key, range: NSRange(key.startIndex..., in: key), withTemplate: "$1_$2"
        )
        return matches(imageKeyPattern, foldingASCIICase(snake))
    }

    /// Data URLs and raw base64 JPEG / PNG prefixes, after JavaScript `trimStart()`.
    static func looksLikeImageData(_ value: String) -> Bool {
        let trimmed = String(String.UnicodeScalarView(
            value.unicodeScalars.drop(while: { javaScriptWhitespace.contains($0.value) })
        ))
        return matches(imageValuePattern, foldingASCIICase(trimmed))
    }

    /// Recursively removes image-bearing keys and image-looking string values from
    /// an outgoing JSON object. Everything else is passed through untouched.
    static func strippingImagePayload(_ object: [String: Any]) -> [String: Any] {
        var cleaned: [String: Any] = [:]
        for (key, value) in object where !isImageBearingKey(key) {
            if let kept = strippingImagePayload(value) { cleaned[key] = kept }
        }
        return cleaned
    }

    /// `nil` means "drop this value". Arrays and nested objects are cleaned in place.
    private static func strippingImagePayload(_ value: Any) -> Any? {
        switch value {
        case let object as [String: Any]:
            return strippingImagePayload(object)
        case let array as [Any]:
            return array.compactMap(strippingImagePayload)
        case let string as String:
            return looksLikeImageData(string) ? nil : string
        default:
            return value
        }
    }

    /// Single choke point for every JSON body this client posts.
    static func encodeRequestBody(_ body: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: strippingImagePayload(body), options: [])
    }

    /// Live store garments are the source of truth. Fixture JSON is an overlay for
    /// bundled ids only — user-added UUIDs are serialized from `StubGarment` (#97).
    /// Fixture overlay rows are stripped of image-bearing keys here; summary rows
    /// never carry one. `encodeRequestBody` re-checks the whole body regardless.
    static func wardrobeRows(from garments: [StubGarment]) -> [[String: Any]] {
        let fixtureById = Dictionary(
            uniqueKeysWithValues: FixtureWardrobeLoader.loadGarmentJSONObjects().compactMap { row -> (String, [String: Any])? in
                guard let id = row["id"] as? String else { return nil }
                return (id.lowercased(), row)
            }
        )
        var wardrobe: [[String: Any]] = []
        for live in garments {
            // D-23: drafts never enter generation / alternatives payloads
            guard live.isReady else { continue }
            if var fixture = fixtureById[live.id.uuidString.lowercased()] {
                fixture["availability"] = live.availability
                fixture["readiness"] = live.readiness.rawValue
                fixture["displayName"] = live.displayName
                if let last = live.lastWornOn {
                    fixture["lastWornOn"] = last
                }
                if let color = live.colorPrimary {
                    fixture["colorPrimary"] = colorDictionary(color)
                }
                if let pattern = live.pattern { fixture["pattern"] = pattern }
                if let surface = live.surface { fixture["surface"] = surface }
                if let formality = live.formality { fixture["formality"] = formality }
                if let warmth = live.warmth { fixture["warmth"] = warmth }
                if let setId = live.setId {
                    fixture["setId"] = setId.uuidString.lowercased()
                }
                if let keep = live.keepTogether {
                    fixture["keepTogether"] = keep
                }
                wardrobe.append(strippingImagePayload(fixture))
            } else {
                wardrobe.append(garmentSummary(from: live))
            }
        }
        return wardrobe
    }

    static func garmentSummary(from g: StubGarment) -> [String: Any] {
        var row: [String: Any] = [
            "id": g.id.uuidString.lowercased(),
            "displayName": g.displayName,
            "slot": g.slot.rawValue,
            "readiness": g.readiness.rawValue,
            "availability": g.availability,
            "seasons": defaultSeasons,
        ]
        if let color = g.colorPrimary {
            row["colorPrimary"] = colorDictionary(color)
        }
        if let pattern = g.pattern { row["pattern"] = pattern }
        if let surface = g.surface { row["surface"] = surface }
        if let formality = g.formality { row["formality"] = formality }
        if let warmth = g.warmth { row["warmth"] = warmth }
        if let last = g.lastWornOn { row["lastWornOn"] = last }
        if let days = g.daysSinceIntake { row["daysSinceIntake"] = days }
        if let setId = g.setId { row["setId"] = setId.uuidString.lowercased() }
        if let keep = g.keepTogether { row["keepTogether"] = keep }
        return row
    }

    static func setRows(from sets: [StubSet]) -> [[String: Any]] {
        sets.map { s in
            var row: [String: Any] = [
                "id": s.id.uuidString.lowercased(),
                "displayName": s.displayName,
                "keepTogether": s.keepTogether,
                "memberGarmentIds": s.memberGarmentIds.map { $0.uuidString.lowercased() },
            ]
            if let notes = s.notes { row["notes"] = notes }
            return row
        }
    }

    static func colorDictionary(_ color: StubColorPrimary) -> [String: Any] {
        var d: [String: Any] = [:]
        if let family = color.family { d["family"] = family }
        if let hex = color.hex { d["hex"] = hex }
        if let name = color.name { d["name"] = name }
        return d
    }

    static func normalizeExcludeSets(_ sets: [[UUID]]) -> [[String]] {
        Array(sets.prefix(excludeGarmentSetsCap)).map { ids in
            ids.map { $0.uuidString.lowercased() }
        }
    }

    static func healthCheck() async -> Bool {
        do {
            let (data, response) = try await urlSession.data(from: healthURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            // Workers and local emit {status:"ok"}; local also keeps {ok:true} (#83 / #90).
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if (obj["ok"] as? Bool) == true { return true }
                if let status = obj["status"] as? String, status.lowercased() == "ok" { return true }
                return false
            }
            return true
        } catch {
            return false
        }
    }

    /// Build GenerateRequest from the live wardrobe (user + fixture overlays).
    static func makeRequestBody(
        garments: [StubGarment],
        sets: [StubSet],
        anchorId: UUID,
        lockedAssignments: [StubOutfitAssignment] = [],
        occasion: String = "WORK_STANDARD",
        occasionFormality: Int = 3,
        temperatureBand: String = "MILD",
        precipitation: Bool = false,
        excludeGarmentSets: [[UUID]] = []
    ) throws -> Data {
        let wardrobe = wardrobeRows(from: garments)
        let anchorKey = anchorId.uuidString.lowercased()
        guard wardrobe.contains(where: { ($0["id"] as? String)?.lowercased() == anchorKey }) else {
            throw ClientError.anchorNotInWardrobe(anchorId)
        }

        let locks: [[String: Any]] = lockedAssignments.compactMap { a in
            guard let gid = a.garmentId else { return nil }
            return [
                "slot": a.slot.rawValue,
                "garmentId": gid.uuidString.lowercased(),
                "isLocked": true,
                "isAnchor": a.isAnchor,
            ]
        }
        var options: [String: Any] = [
            "requireSlots": ["TOP", "BOTTOM", "FOOTWEAR"],
        ]
        if !excludeGarmentSets.isEmpty {
            options["excludeGarmentSets"] = normalizeExcludeSets(excludeGarmentSets)
        }
        var body: [String: Any] = [
            "wardrobe": wardrobe,
            "sets": setRows(from: sets),
            "anchorGarmentId": anchorKey,
            "context": [
                "occasion": occasion,
                "occasionFormality": occasionFormality,
                "temperatureBand": temperatureBand,
                "precipitation": precipitation,
            ] as [String: Any],
            "options": options,
        ]
        if !locks.isEmpty {
            body["lockedAssignments"] = locks
        }
        return try encodeRequestBody(body)
    }

    static func generate(
        garments: [StubGarment],
        sets: [StubSet],
        anchorId: UUID,
        lockedAssignments: [StubOutfitAssignment] = [],
        occasion: String = "WORK_STANDARD",
        occasionFormality: Int = 3,
        temperatureBand: String = "MILD",
        precipitation: Bool = false,
        excludeGarmentSets: [[UUID]] = [],
        flight: EngineDataTask
    ) async throws -> GenerateResponse {
        // Fail closed before assembling wardrobe for remote hosts (#175 / D-46).
        if try requiresDeviceToken(for: baseURL) && !DeviceTokenStore.hasToken {
            throw ClientError.missingDeviceToken
        }
        let payload = try makeRequestBody(
            garments: garments,
            sets: sets,
            anchorId: anchorId,
            lockedAssignments: lockedAssignments,
            occasion: occasion,
            occasionFormality: occasionFormality,
            temperatureBand: temperatureBand,
            precipitation: precipitation,
            excludeGarmentSets: excludeGarmentSets
        )
        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try applyAuth(to: &request)
        request.timeoutInterval = 15
        request.httpBody = payload

        emitLifecycle(.constructed, request: request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await flight.data(for: request)
        } catch {
            throw ClientError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(-1, "No HTTP response")
        }

        if http.statusCode == 400 {
            if let problem = try? JSONDecoder().decode(ProblemBody.self, from: data) {
                throw ClientError.problem(problem)
            }
            throw ClientError.http(400, String(data: data, encoding: .utf8) ?? "")
        }

        if http.statusCode == 401 {
            throw ClientError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try JSONDecoder().decode(GenerateResponse.self, from: data)
        } catch {
            throw ClientError.decode(error)
        }
    }

    static func mapToStubOutfit(_ response: GenerateResponse, anchorId: UUID) -> StubOutfit {
        let assignments: [StubOutfitAssignment] = response.assignments.compactMap { a in
            guard let slot = StubSlot(rawValue: a.slot) else { return nil }
            let gid = a.garmentId.flatMap(UUID.init(uuidString:))
            let isAnchor = a.isAnchor ?? (gid == anchorId)
            return StubOutfitAssignment(
                slot: slot,
                garmentId: gid,
                gapReason: a.gapReason,
                isAnchor: isAnchor,
                isLocked: a.isLocked ?? false
            )
        }
        let summary = response.rationale?.summary
            ?? "Deterministic local outfit (S1→S2→builder)."
        let outfitId = UUID(uuidString: response.outfitId) ?? UUID()
        return StubOutfit(
            id: outfitId,
            assignments: assignments,
            rationaleSummary: summary,
            offlineCached: false
        )
    }

    static func makeAlternativesBody(
        slot: StubSlot,
        outfit: StubOutfit,
        garments: [StubGarment],
        sets: [StubSet],
        limit: Int = 8,
        occasion: String = "WORK_STANDARD",
        occasionFormality: Int = 3,
        temperatureBand: String = "MILD",
        precipitation: Bool = false
    ) throws -> Data {
        let wardrobe = wardrobeRows(from: garments)
        let assignments: [[String: Any]] = outfit.assignments.map { a in
            var d: [String: Any] = [
                "slot": a.slot.rawValue,
                "isAnchor": a.isAnchor,
                "isLocked": a.isLocked,
            ]
            if let gid = a.garmentId {
                d["garmentId"] = gid.uuidString.lowercased()
            }
            if let gap = a.gapReason {
                d["gapReason"] = gap
            }
            return d
        }
        let body: [String: Any] = [
            "slot": slot.rawValue,
            "currentAssignments": assignments,
            "wardrobe": wardrobe,
            "sets": setRows(from: sets),
            "limit": limit,
            "context": [
                "occasion": occasion,
                "occasionFormality": occasionFormality,
                "temperatureBand": temperatureBand,
                "precipitation": precipitation,
            ] as [String: Any],
            "profile": [
                "activeRules": [] as [Any],
            ] as [String: Any],
        ]
        return try encodeRequestBody(body)
    }

    static func fetchAlternatives(
        slot: StubSlot,
        outfit: StubOutfit,
        garments: [StubGarment],
        sets: [StubSet],
        occasion: String = "WORK_STANDARD",
        occasionFormality: Int = 3,
        temperatureBand: String = "MILD",
        precipitation: Bool = false
    ) async throws -> AlternativesResponse {
        if try requiresDeviceToken(for: baseURL) && !DeviceTokenStore.hasToken {
            throw ClientError.missingDeviceToken
        }
        let payload = try makeAlternativesBody(
            slot: slot,
            outfit: outfit,
            garments: garments,
            sets: sets,
            occasion: occasion,
            occasionFormality: occasionFormality,
            temperatureBand: temperatureBand,
            precipitation: precipitation
        )
        var request = URLRequest(url: alternativesURL)
        request.httpMethod = "POST"
        try applyAuth(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = payload
        emitLifecycle(.constructed, request: request)
        emitLifecycle(.dispatched, request: request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ClientError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(-1, "No HTTP response")
        }
        if http.statusCode == 400 {
            if let problem = try? JSONDecoder().decode(ProblemBody.self, from: data) {
                throw ClientError.problem(problem)
            }
            throw ClientError.http(400, String(data: data, encoding: .utf8) ?? "")
        }
        if http.statusCode == 401 {
            throw ClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(AlternativesResponse.self, from: data)
        } catch {
            throw ClientError.decode(error)
        }
    }

    static func mapAlternatives(
        _ response: AlternativesResponse,
        garments: [StubGarment]
    ) -> (alts: [StubSwapAlternative], emptyReason: String?) {
        let byId = Dictionary(uniqueKeysWithValues: garments.map { ($0.id.uuidString.lowercased(), $0) })
        var out: [StubSwapAlternative] = []
        for row in response.alternatives {
            guard let g = byId[row.garmentId.lowercased()] else { continue }
            let partners = (row.setPartnerIds ?? []).compactMap { UUID(uuidString: $0) }
            out.append(
                StubSwapAlternative(
                    id: g.id,
                    garment: g,
                    reason: row.reason,
                    score: row.score,
                    setPartnerIds: partners
                )
            )
        }
        return (out, response.emptyReason)
    }

}
