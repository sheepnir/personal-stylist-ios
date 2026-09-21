import XCTest
@testable import PersonalStylist

final class ReadyBatchTests: XCTestCase {
    func testConstraintTextRoundTripsWithoutChangingMeaning() {
        let notes = "Not nothing itchy, but avoid wool. Keep punctuation."
        let parsed = ProfileFieldCopy.splitConstraints(notes)
        XCTAssertTrue(parsed.selected.isEmpty)
        XCTAssertEqual(ProfileFieldCopy.encodeConstraints(selected: parsed.selected, extra: parsed.extra), notes)
        let encoded = ProfileFieldCopy.encodeConstraints(selected: ["no tight collars"], extra: notes)
        let decoded = ProfileFieldCopy.splitConstraints(encoded)
        XCTAssertEqual(decoded.selected, ["no tight collars"])
        XCTAssertEqual(decoded.extra, notes)
    }

    private func garment(
        _ name: String,
        slot: StubSlot,
        ready: Bool = true,
        availability: String = "AVAILABLE"
    ) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
            readiness: ready ? .ready : .draft,
            availability: availability,
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: ready ? "SOLID" : nil,
            surface: ready ? "SMOOTH" : nil,
            imagePath: nil,
            formality: ready ? 3 : nil,
            warmth: ready ? 3 : nil,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
    }

    func testCoverageNamesExactMissingSlotsAndIgnoresDraftsAndRetired() {
        let items = [
            garment("T1", slot: .top),
            garment("Draft top", slot: .top, ready: false),
            garment("Retired top", slot: .top, availability: "RETIRED"),
            garment("B1", slot: .bottom),
        ]
        let snap = WardrobeCoverage.evaluate(items)
        XCTAssertFalse(snap.meetsGenerationMinimum)
        XCTAssertEqual(snap.missing.map(\.slot), [.top, .bottom, .footwear])
        XCTAssertEqual(snap.draftCount, 1)
        XCTAssertEqual(
            snap.coverageLine,
            "Add 1 more top, 1 more pair of trousers or jeans, and 1 pair of footwear and I can build outfits."
        )
        XCTAssertEqual(snap.draftsLine, "1 garment needs details before it can be used")
    }

    func testCoverageMeetsMinimumAndThinJacketSuggestion() {
        let items = [
            garment("T1", slot: .top),
            garment("T2", slot: .top),
            garment("B1", slot: .bottom),
            garment("B2", slot: .bottom),
            garment("S1", slot: .footwear),
        ]
        let snap = WardrobeCoverage.evaluate(items)
        XCTAssertTrue(snap.meetsGenerationMinimum)
        XCTAssertNil(snap.coverageLine)
        XCTAssertEqual(snap.thinSuggestion, "Add a jacket to unlock smarter work outfits.")
    }

    func testCoverageEmptyWardrobeListsFullMinimum() {
        let snap = WardrobeCoverage.evaluate([])
        XCTAssertEqual(
            snap.coverageLine,
            "Add 2 tops, 2 pairs of trousers or jeans, and 1 pair of footwear and I can build outfits."
        )
    }

    func testColorFamilyMatchStoresHexForSwatch() {
        let navy = ColorFamilyCatalog.match(family: "navy", name: "Navy", hex: nil)
        XCTAssertEqual(navy?.hex, "#1B2A4A")
        XCTAssertEqual(ColorFamilyCatalog.resolvedHex(family: "burgundy", name: nil, hex: nil), "#6E2A36")
        XCTAssertEqual(ColorFamilyCatalog.primary.count, 16)
        XCTAssertTrue(ColorFamilyCatalog.more.contains(where: { $0.id == "orange" }))
    }

    func testImageSizeClasses() {
        XCTAssertEqual(GarmentImagePresentation.inferred(from: 72), .tiny)
        XCTAssertEqual(GarmentImagePresentation.inferred(from: 120), .card)
        XCTAssertEqual(GarmentImagePresentation.inferred(from: 280), .hero)
    }

    func testProfileFieldRoundTripDoesNotInventFounderLiterals() {
        let week = ProfileFieldCopy.encodeTypicalWeek(selected: ["Work", "Weekend"], extra: "")
        XCTAssertEqual(week, "Work, Weekend")
        let parsed = ProfileFieldCopy.parseTypicalWeek(week)
        XCTAssertEqual(parsed.selected, ["Work", "Weekend"])

        let goals = ProfileFieldCopy.encodeGoals(selected: ["look more polished"], extra: "custom")
        XCTAssertEqual(goals, ["look more polished", "custom"])

        XCTAssertEqual(
            ProfileFieldCopy.workEnvironmentLabel(for: "BUSINESS_CASUAL"),
            "Jacket for meetings, relaxed otherwise"
        )
        XCTAssertFalse(ProfileFieldCopy.goalOptions.contains(where: { $0.localizedCaseInsensitiveContains("VP") }))
    }
}
