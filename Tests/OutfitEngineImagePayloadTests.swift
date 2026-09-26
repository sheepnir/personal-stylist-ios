import XCTest
@testable import PersonalStylist

/// The Worker rejects any body carrying an image-bearing key or image-looking
/// value with 415 `IMAGE_NOT_ALLOWED` (VF-03, fail-closed). Bundled fixture rows
/// carry a local `imagePath`, so the client must strip it before posting.
final class OutfitEngineImagePayloadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Self.workerConsentISO8601WithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        Self.workerConsentISO8601Plain.formatOptions = [.withInternetDateTime]
    }

    override func tearDown() {
        EngineURLSessionStub.tearDownClientHooks()
        super.tearDown()
    }

    // MARK: Independent oracle — the Worker's rule, re-stated in the test

    private static let workerConsentFieldPath = "privacyConsent.wardrobeImagesAcceptedAt"
    private static let workerForbiddenTokens = [
        "image", "imagedata", "imagebase64", "thumbnail", "thumb", "photo",
        "masterimage", "processedimage", "pixeldata", "bitmap",
        "imagery", "photography", "thumbsup",
    ]
    private static let workerValuePattern = try! NSRegularExpression(
        pattern: "^data:image/|^/9j/|^ivborw0kggo"
    )
    private static let workerConsentISO8601WithFraction = ISO8601DateFormatter()
    private static let workerConsentISO8601Plain = ISO8601DateFormatter()

    /// ECMAScript WhiteSpace + LineTerminator — what `String.prototype.trimStart` removes.
    static let ecmaScriptWhitespace: [UInt32] = [
        0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
        0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
    ]

    /// JavaScript `i` on an ASCII pattern folds A–Z only.
    private static func asciiLowercased(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map {
            (0x41...0x5A).contains($0.value) ? Unicode.Scalar($0.value + 0x20)! : $0
        }))
    }

    private static func jsTrimStart(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.drop { ecmaScriptWhitespace.contains($0.value) }))
    }

    private static func normalizeWorkerKey(_ key: String) -> String {
        var normalized = ""
        for scalar in key.unicodeScalars {
            if (0x41...0x5A).contains(scalar.value) {
                normalized.unicodeScalars.append(Unicode.Scalar(scalar.value + 0x20)!)
            } else if scalar.value != 0x5F && scalar.value != 0x2D {
                normalized.unicodeScalars.append(scalar)
            }
        }
        return normalized
    }

    private static func workerSegmentImageBearing(_ key: String) -> Bool {
        let normalized = normalizeWorkerKey(key)
        return workerForbiddenTokens.contains { normalized.contains($0) }
    }

    private static func workerAllowedConsent(_ value: Any) -> Bool {
        guard let string = value as? String, !string.isEmpty, string.count <= 64 else { return false }
        guard string.contains("T") else { return false }
        if workerConsentISO8601WithFraction.date(from: string) != nil { return true }
        return workerConsentISO8601Plain.date(from: string) != nil
    }

    private static func workerJoinPath(_ parent: String, _ key: String) -> String {
        parent.isEmpty ? key : "\(parent).\(key)"
    }

    /// Same traversal as `containsImage` in `backend/workers/src/validation.ts`.
    /// Returns the offending key or value prefix, or nil when the body is clean.
    private static func workerImageFinding(in value: Any, path: String = "") -> String? {
        if let s = value as? String {
            let t = asciiLowercased(jsTrimStart(s))
            if workerValuePattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                return "value \(t.prefix(16))"
            }
            return nil
        }
        if let array = value as? [Any] {
            for child in array {
                if let found = workerImageFinding(in: child, path: path) { return found }
            }
            return nil
        }
        if let object = value as? [String: Any] {
            for (key, child) in object {
                let keyPath = workerJoinPath(path, key)
                if keyPath == workerConsentFieldPath {
                    if !workerAllowedConsent(child) { return "consent \(keyPath)" }
                    continue
                }
                if workerSegmentImageBearing(key) { return "key \(key)" }
                if let found = workerImageFinding(in: child, path: keyPath) { return found }
            }
        }
        return nil
    }

    private static func fixtureBackedGarments(minCount: Int) throws -> (garments: [StubGarment], rows: [String: [String: Any]]) {
        let rows = Dictionary(
            uniqueKeysWithValues: FixtureWardrobeLoader.loadGarmentJSONObjects().compactMap { row -> (String, [String: Any])? in
                guard let id = row["id"] as? String else { return nil }
                return (id.lowercased(), row)
            }
        )
        let garments = FixtureWardrobeLoader.loadGarments().filter {
            $0.isReady && rows[$0.id.uuidString.lowercased()] != nil
        }
        guard garments.count >= minCount else {
            throw XCTSkip("need \(minCount) READY fixture-backed garments")
        }
        return (Array(garments.prefix(max(minCount, 8))), rows)
    }

    // MARK: (a) fixture row loses `imagePath`, keeps everything else

    func testFixtureBackedWardrobeRowDropsImagePathAndKeepsOtherFields() throws {
        let (garments, rows) = try Self.fixtureBackedGarments(minCount: 1)
        let garment = garments[0]
        let fixture = try XCTUnwrap(rows[garment.id.uuidString.lowercased()])
        XCTAssertNotNil(fixture["imagePath"], "fixture rows are expected to carry a local image reference")

        let sent = try XCTUnwrap(OutfitEngineClient.wardrobeRows(from: [garment]).first)

        XCTAssertNil(sent["imagePath"])
        XCTAssertEqual(Set(sent.keys), Set(fixture.keys).subtracting(["imagePath"]))
        // Engine-relevant fields survive verbatim (overlay fields aside).
        for key in ["id", "slot", "category", "seasons", "materials", "fit", "daysSinceIntake", "isFavorite"] {
            XCTAssertEqual(sent[key] as? NSObject, fixture[key] as? NSObject, key)
        }
        XCTAssertEqual(sent["availability"] as? String, garment.availability)
        XCTAssertEqual(sent["readiness"] as? String, garment.readiness.rawValue)
    }

    // MARK: (b) nested objects and arrays are cleaned

    func testStrippingIsRecursiveAcrossObjectsAndArrays() {
        let body: [String: Any] = [
            "wardrobe": [
                ["id": "g1", "slot": "TOP", "imagePath": "images/x.svg", "thumbnailURL": "t.png"],
                ["id": "g2", "slot": "BOTTOM", "media": ["photo": "p.jpg", "masterImage": "m.png", "note": "keep"]],
            ],
            "sets": [["id": "s1", "memberGarmentIds": ["g1", "g2"], "PIXELDATA": "x"]],
            "context": ["occasion": "WORK_STANDARD", "bitmap": [1, 2]],
            "anchorGarmentId": "g1",
        ]

        let cleaned = OutfitEngineClient.strippingImagePayload(body)

        XCTAssertNil(Self.workerImageFinding(in: cleaned))
        let wardrobe = cleaned["wardrobe"] as? [[String: Any]]
        XCTAssertEqual(wardrobe?.count, 2)
        XCTAssertEqual(Set((wardrobe?[0] ?? [:]).keys), ["id", "slot"])
        XCTAssertEqual((wardrobe?[1]["media"] as? [String: Any])?.keys.sorted(), ["note"])
        XCTAssertEqual(Set(((cleaned["sets"] as? [[String: Any]])?[0] ?? [:]).keys), ["id", "memberGarmentIds"])
        XCTAssertEqual((cleaned["context"] as? [String: Any])?.keys.sorted(), ["occasion"])
        XCTAssertEqual(cleaned["anchorGarmentId"] as? String, "g1")
    }

    func testKeyNormalisationMirrorsWorker() {
        for key in ["image", "thumbnails", "imagePath", "image_path", "image-path", "imagepath", "image_blob", "ImageData", "thumbnail", "thumb", "photoUrl", "masterImage", "processedImage", "pixeldata", "pixelData", "PIXELDATA", "bitmap", "IMAGEBASE64", "garmentimages", "imagery", "photography", "thumbs_up"] {
            XCTAssertTrue(OutfitEngineClient.isImageBearingKey(key), key)
        }
        for key in ["id", "slot", "displayName", "colorPrimary", "readiness", "memberGarmentIds", "policyVersion"] {
            XCTAssertFalse(OutfitEngineClient.isImageBearingKey(key), key)
        }
        XCTAssertTrue(OutfitEngineClient.isImageBearingKey("wardrobeImagesAcceptedAt"))
    }

    func testGuardedEndpointAndFixtureGarmentKeysAreNotImageBearing() {
        let keys = [
            "wardrobe", "sets", "anchorGarmentId", "context", "options", "lockedAssignments",
            "occasion", "occasionFormality", "temperatureBand", "precipitation",
            "requireSlots", "excludeGarmentSets", "currentAssignments", "limit", "profile",
            "activeRules", "garmentId", "isLocked", "isAnchor", "gapReason", "keepTogether",
            "notes", "availability", "displayNameSource", "category", "colorSecondary",
            "pattern", "materials", "surface", "formality", "warmth", "seasons", "fit",
            "lastWornOn", "daysSinceIntake", "isFavorite", "wantToWearMore", "comfortIssue",
            "setId", "attributeConfidence", "family", "hex", "name",
        ]
        for key in keys {
            XCTAssertFalse(OutfitEngineClient.isImageBearingKey(key), key)
        }
    }

    func testOpenApiImageAndThumbnailKeysRejectInWorkerOracle() {
        XCTAssertNotNil(Self.workerImageFinding(in: ["thumbnails": []]))
        XCTAssertNotNil(Self.workerImageFinding(in: ["image": ["data": "x", "mediaType": "image/png"]]))
    }

    func testConsentExceptionPathIsPreservedWhenValid() {
        let body: [String: Any] = [
            "privacyConsent": [
                "wardrobeImagesAcceptedAt": "2026-09-20T12:00:00Z",
                "policyVersion": "2026-09-01",
            ],
            "displayName": "ok",
        ]
        let cleaned = OutfitEngineClient.strippingImagePayload(body)
        let consent = cleaned["privacyConsent"] as? [String: Any]
        XCTAssertEqual(consent?["wardrobeImagesAcceptedAt"] as? String, "2026-09-20T12:00:00Z")
        XCTAssertNil(Self.workerImageFinding(in: cleaned))
    }

    func testConsentExceptionRejectedAtWrongPathOrBadValue() {
        XCTAssertNotNil(Self.workerImageFinding(in: ["wardrobeImagesAcceptedAt": "2026-09-20T12:00:00Z"]))
        XCTAssertNotNil(Self.workerImageFinding(in: [
            "privacyConsent": ["wardrobeImagesAcceptedAt": "not-a-date", "policyVersion": "1"],
        ]))
        XCTAssertNotNil(Self.workerImageFinding(in: [
            "privacyConsent": ["wardrobeImagesAcceptedAt": "2026-09-20", "policyVersion": "1"],
        ]))
        let bad = OutfitEngineClient.strippingImagePayload([
            "privacyConsent": ["wardrobeImagesAcceptedAt": "not-a-date", "policyVersion": "1"],
        ])
        XCTAssertNil(bad["privacyConsent"])
    }

    // MARK: (c) image-looking values are dropped

    func testImageLookingStringValuesAreDropped() {
        let body: [String: Any] = [
            "notes": "data:image/png;base64,AAAA",
            "attachments": ["  /9j/4AAQSkZJRg", "iVBORw0KGgoAAAANSUhEUg", "plain text"],
            "displayName": "Navy Oxford Shirt",
        ]

        let cleaned = OutfitEngineClient.strippingImagePayload(body)

        XCTAssertNil(cleaned["notes"])
        XCTAssertEqual(cleaned["attachments"] as? [String], ["plain text"])
        XCTAssertEqual(cleaned["displayName"] as? String, "Navy Oxford Shirt")
        XCTAssertNil(Self.workerImageFinding(in: cleaned))
    }

    // MARK: JavaScript parity — `trimStart()` whitespace and ASCII-only case folding

    func testByteOrderMarkPrefixedDataURLIsStripped() {
        // JS `trimStart()` removes U+FEFF, so the Worker sees `data:image/` and rejects it.
        let value = "\u{FEFF}data:image/png;base64,AAAA"
        XCTAssertTrue(OutfitEngineClient.looksLikeImageData(value))
        XCTAssertNil(OutfitEngineClient.strippingImagePayload(["notes": value])["notes"])
    }

    func testNextLinePrefixedDataURLIsKeptLikeTheWorker() {
        // U+0085 is not ECMAScript whitespace: the Worker keeps the value, so must we.
        let value = "\u{0085}data:image/png;base64,AAAA"
        XCTAssertFalse(OutfitEngineClient.looksLikeImageData(value))
        XCTAssertEqual(OutfitEngineClient.strippingImagePayload(["notes": value])["notes"] as? String, value)
        XCTAssertNil(Self.workerImageFinding(in: ["notes": value]))
    }

    func testEveryECMAScriptWhitespaceScalarIsTrimmedBeforeMatching() {
        for scalar in Self.ecmaScriptWhitespace {
            let prefix = String(Unicode.Scalar(scalar)!)
            let hex = String(format: "U+%04X", scalar)
            XCTAssertTrue(OutfitEngineClient.looksLikeImageData(prefix + "data:image/png;base64,AAAA"), hex)
            XCTAssertTrue(OutfitEngineClient.looksLikeImageData(prefix + prefix + "/9j/4AAQ"), hex)
            XCTAssertTrue(OutfitEngineClient.looksLikeImageData(prefix + "iVBORw0KGgoAAAA"), hex)
        }
        // A non-whitespace prefix is not trimmed.
        XCTAssertFalse(OutfitEngineClient.looksLikeImageData("x data:image/png;base64,AAAA"))
    }

    func testCaseFoldingIsASCIIOnly() {
        // `ſ` (U+017F) does not fold to `s` under the JS `i` flag, so the Worker keeps this key.
        XCTAssertFalse(OutfitEngineClient.isImageBearingKey("maſterimage"))
        XCTAssertEqual(OutfitEngineClient.strippingImagePayload(["maſterimage": 1])["maſterimage"] as? Int, 1)
        XCTAssertNil(Self.workerImageFinding(in: ["maſterimage": 1]))
        // ASCII case still folds on both sides.
        XCTAssertTrue(OutfitEngineClient.isImageBearingKey("MASTERIMAGE"))
        XCTAssertTrue(OutfitEngineClient.looksLikeImageData("DATA:IMAGE/PNG;base64,AAAA"))
        XCTAssertTrue(OutfitEngineClient.looksLikeImageData("IVBORW0KGGO"))
        // Kelvin sign (U+212A) is not ASCII `k`.
        XCTAssertFalse(OutfitEngineClient.looksLikeImageData("iVBORw0\u{212A}Ggo"))
    }

    // MARK: (d) the bodies the client actually encodes carry nothing image-bearing

    func testGenerateBodyContainsNoImagePayload() throws {
        let (garments, _) = try Self.fixtureBackedGarments(minCount: 3)
        let anchor = garments[0]
        let locked = try XCTUnwrap(garments.first { $0.slot != anchor.slot })
        // A BOM-prefixed data URL rides in on the only free-text set field; the
        // Worker's `trimStart()` would expose it, so the client must drop it.
        let bomDataURL = "\u{FEFF}data:image/png;base64,AAAA"
        let sets = [StubSet(id: UUID(), displayName: "Suit", keepTogether: true, memberGarmentIds: [anchor.id, locked.id], notes: bomDataURL)]
        let data = try OutfitEngineClient.makeRequestBody(
            garments: garments,
            sets: sets,
            anchorId: anchor.id,
            lockedAssignments: [StubOutfitAssignment(slot: locked.slot, garmentId: locked.id, isAnchor: false, isLocked: true)],
            excludeGarmentSets: [[anchor.id, garments[2].id]]
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(Self.workerImageFinding(in: body))
        XCTAssertEqual((body["wardrobe"] as? [[String: Any]])?.count, garments.count)
        let sentSet = try XCTUnwrap((body["sets"] as? [[String: Any]])?.first)
        XCTAssertNil(sentSet["notes"], "BOM-prefixed data URL must not reach the Worker")
        XCTAssertEqual(sentSet["displayName"] as? String, "Suit")
        Self.exportIfRequested(data, name: "generate-body.json")
    }

    func testAlternativesBodyContainsNoImagePayload() throws {
        let (garments, _) = try Self.fixtureBackedGarments(minCount: 3)
        let outfit = StubOutfit(
            id: UUID(),
            assignments: garments.prefix(3).enumerated().map { i, g in
                StubOutfitAssignment(slot: g.slot, garmentId: g.id, isAnchor: i == 0)
            },
            rationaleSummary: "",
            offlineCached: false
        )
        let data = try OutfitEngineClient.makeAlternativesBody(
            slot: garments[1].slot, outfit: outfit, garments: garments, sets: []
        )
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(Self.workerImageFinding(in: body))
        XCTAssertEqual((body["wardrobe"] as? [[String: Any]])?.count, garments.count)
        Self.exportIfRequested(data, name: "alternatives-body.json")
    }

    /// End to end through `generate` / `fetchAlternatives`: the bytes handed to
    /// URL loading are the ones checked, so a future payload change cannot regress.
    func testDispatchedRequestsCarryNoImagePayload() async throws {
        let (garments, _) = try Self.fixtureBackedGarments(minCount: 3)
        let generateResponse = Data("""
        {"outfitId":"\(UUID().uuidString.lowercased())","assignments":[{"slot":"TOP","garmentId":"\(garments[0].id.uuidString.lowercased())","isAnchor":true}]}
        """.utf8)
        let alternativesResponse = Data(#"{"slot":"TOP","alternatives":[]}"#.utf8)
        EngineURLSessionStub.installClientHooks { request in
            .http(status: 200, body: request.url?.path.hasSuffix("/alternatives") == true ? alternativesResponse : generateResponse)
        }

        _ = try await OutfitEngineClient.generate(
            garments: garments, sets: [], anchorId: garments[0].id, flight: OutfitEngineClient.EngineDataTask()
        )
        let outfit = StubOutfit(
            id: UUID(),
            assignments: [StubOutfitAssignment(slot: garments[0].slot, garmentId: garments[0].id, isAnchor: true)],
            rationaleSummary: "",
            offlineCached: false
        )
        _ = try await OutfitEngineClient.fetchAlternatives(slot: garments[0].slot, outfit: outfit, garments: garments, sets: [])

        let recorded = RecordingURLProtocol.recorded
        XCTAssertEqual(recorded.map(\.path).map { $0.split(separator: "/").last.map(String.init) }, ["generate", "alternatives"])
        for request in recorded {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
            XCTAssertNil(Self.workerImageFinding(in: body), request.path)
            XCTAssertFalse((body["wardrobe"] as? [[String: Any]])?.isEmpty ?? true, request.path)
        }
    }

    /// Opt-in: `TEST_RUNNER_ENGINE_BODY_EXPORT_DIR=<dir>` writes the encoded bodies
    /// so they can be replayed against a locally running Worker.
    private static func exportIfRequested(_ data: Data, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ENGINE_BODY_EXPORT_DIR"], !dir.isEmpty else { return }
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }
}
