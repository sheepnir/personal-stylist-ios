import XCTest
@testable import PersonalStylist

/// The Worker rejects any body carrying an image-bearing key or image-looking
/// value with 415 `IMAGE_NOT_ALLOWED` (VF-03, fail-closed). Bundled fixture rows
/// carry a local `imagePath`, so the client must strip it before posting.
final class OutfitEngineImagePayloadTests: XCTestCase {
    override func tearDown() {
        EngineURLSessionStub.tearDownClientHooks()
        super.tearDown()
    }

    // MARK: Independent oracle — the Worker's rule, re-stated in the test

    private static let workerKeyPattern = try! NSRegularExpression(
        pattern: "(^|[^a-z])(image|imagedata|imagebase64|thumbnail|thumb|photo|masterimage|processedimage|pixeldata|bitmap)([^a-z]|$)",
        options: [.caseInsensitive]
    )
    private static let workerValuePattern = try! NSRegularExpression(
        pattern: "^data:image/|^/9j/|^iVBORw0KGgo",
        options: [.caseInsensitive]
    )

    /// Same traversal as `containsImage` in `backend/workers/src/validation.ts`.
    /// Returns the offending key or value prefix, or nil when the body is clean.
    private static func workerImageFinding(in value: Any) -> String? {
        var pending: [Any] = [value]
        while let item = pending.popLast() {
            if let s = item as? String {
                let t = String(s.drop(while: \.isWhitespace))
                if workerValuePattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil {
                    return "value \(t.prefix(16))"
                }
            } else if let array = item as? [Any] {
                pending.append(contentsOf: array)
            } else if let object = item as? [String: Any] {
                for (key, child) in object {
                    let snake = key.replacingOccurrences(
                        of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression
                    )
                    if workerKeyPattern.firstMatch(in: snake, range: NSRange(snake.startIndex..., in: snake)) != nil {
                        return "key \(key)"
                    }
                    pending.append(child)
                }
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
        for key in ["image", "imagePath", "image_path", "ImageData", "thumbnail", "thumb", "photoUrl", "masterImage", "processedImage", "pixeldata", "PIXELDATA", "bitmap", "IMAGEBASE64"] {
            XCTAssertTrue(OutfitEngineClient.isImageBearingKey(key), key)
        }
        // Same verdicts as the Worker, including its camelCase quirk: `pixelData`
        // normalises to `pixel_Data`, which the `pixeldata` token no longer spans.
        for key in ["id", "slot", "displayName", "colorPrimary", "thumbs_up", "photography", "imagery", "readiness", "pixelData"] {
            XCTAssertFalse(OutfitEngineClient.isImageBearingKey(key), key)
        }
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

    // MARK: (d) the bodies the client actually encodes carry nothing image-bearing

    func testGenerateBodyContainsNoImagePayload() throws {
        let (garments, _) = try Self.fixtureBackedGarments(minCount: 3)
        let anchor = garments[0]
        let locked = try XCTUnwrap(garments.first { $0.slot != anchor.slot })
        let sets = [StubSet(id: UUID(), displayName: "Suit", keepTogether: true, memberGarmentIds: [anchor.id, locked.id], notes: nil)]
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
