import XCTest
@testable import PersonalStylist

/// D-75 — human copy only. No HTTP, URLs, or persistence tokens.
final class DailyWearCopyTests: XCTestCase {
    func testPickerAndLoggedTodayCopyHasNoMachineTokens() {
        let joined = [
            DailyWearCopy.pickerTitle,
            DailyWearCopy.wearingThis,
            DailyWearCopy.changeWhatIWore,
            DailyWearCopy.useCorrectionInstead,
            DailyWearCopy.loggedToday,
            DailyWearCopy.logSelected,
            DailyWearCopy.updateSelected,
            DailyWearCopy.tryAgain,
            DailyWearCopy.done,
            DailyWearCopy.cancel,
            DailyWearCopy.newWearSubtitle,
            DailyWearCopy.correctionSubtitle,
            DailyWearCopy.emptyReady,
            DailyWearCopy.emptySelection,
            DailyWearCopy.emptySearch,
            DailyWearCopy.notAvailableToday,
            DailyWearCopy.searchPrompt,
            DailyWearCopy.persistFailed,
            DailyWearCopy.alreadyLogged,
            DailyWearCopy.blockedDrafts,
            DailyWearCopy.replacingSession,
            DailyWearCopy.loggedTodayToast,
            DailyWearCopy.updatedTodayToast,
            DailyWearCopy.successTitle,
            DailyWearCopy.undoneTitle,
            DailyWearCopy.loggedAsWorn,
            DailyWearCopy.returnToOutfit,
            DailyWearCopy.loggedCount(1),
            DailyWearCopy.loggedCount(3),
            DailyWearCopy.loggedTodayHint,
            DailyWearCopy.searchHint,
            DailyWearCopy.submitHintNew,
            DailyWearCopy.submitHintCorrection,
            DailyWearCopy.persistFailedHint,
            DailyWearCopy.selectedValue,
            DailyWearCopy.notSelectedValue,
        ].joined(separator: "\n")

        XCTAssertEqual(DailyWearCopy.pickerTitle, "What did you wear?")
        XCTAssertEqual(DailyWearCopy.wearingThis, "Wearing this")
        XCTAssertEqual(DailyWearCopy.changeWhatIWore, "Change what I wore")
        XCTAssertEqual(DailyWearCopy.useCorrectionInstead, "Today is already logged. Use Change what I wore.")
        XCTAssertEqual(DailyWearCopy.loggedToday, "Logged today")
        XCTAssertEqual(DailyWearCopy.emptyReady, "No ready garments yet. Finish details on a draft first.")
        XCTAssertFalse(DailyWearCopy.containsMachineToken(joined))
    }

    func testLoggedTodayRowNamesPiecesAndTime() {
        let wornOn = Date(timeIntervalSince1970: 1_726_920_000)
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US_POSIX")
        let title = DailyWearCopy.rowTitle(leadName: "Navy Oxford Shirt", extraCount: 3)
        XCTAssertEqual(title, "Navy Oxford Shirt + 3 more")
        XCTAssertEqual(DailyWearCopy.rowTitle(leadName: "Navy Oxford Shirt", extraCount: 1), "Navy Oxford Shirt + 1 more")
        XCTAssertEqual(DailyWearCopy.rowTitle(leadName: "Navy Oxford Shirt", extraCount: 0), "Navy Oxford Shirt")

        let line = DailyWearCopy.rowLine(
            leadName: "Navy Oxford Shirt",
            extraCount: 3,
            wornOn: wornOn,
            locale: locale,
            calendar: calendar
        )
        XCTAssertTrue(line.contains("Navy Oxford Shirt + 3 more"))
        XCTAssertTrue(line.contains("·"))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(line))

        let ax = DailyWearCopy.rowAccessibility(
            leadName: "Navy Oxford Shirt",
            extraCount: 3,
            wornOn: wornOn,
            locale: locale,
            calendar: calendar
        )
        XCTAssertTrue(ax.contains(DailyWearCopy.loggedToday))
        XCTAssertTrue(ax.contains(DailyWearCopy.changeWhatIWore))
        XCTAssertTrue(ax.contains("Wearing this is off"))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(ax))
    }

    func testSearchMatchesNameAndSlotLabel() {
        let top = StubGarment(
            id: UUID(),
            displayName: "Navy Oxford Shirt",
            slot: .top,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 3,
            warmth: 3,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
        XCTAssertTrue(DailyWearCopy.matchesSearch(top, query: "oxford"))
        XCTAssertTrue(DailyWearCopy.matchesSearch(top, query: "Top"))
        XCTAssertFalse(DailyWearCopy.matchesSearch(top, query: "footwear"))
        XCTAssertTrue(DailyWearCopy.matchesSearch(top, query: "  "))
    }

    func testPickerRowLabelSpeaksNameSlotAndAvailability() {
        var laundry = StubGarment(
            id: UUID(),
            displayName: "Ink Trousers",
            slot: .bottom,
            readiness: .ready,
            availability: "LAUNDRY",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 3,
            warmth: 3,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
        laundry.availability = "LAUNDRY"
        let label = DailyWearCopy.pickerRowLabel(laundry)
        XCTAssertTrue(label.contains("Ink Trousers"))
        XCTAssertTrue(label.contains(StubSlot.bottom.displayLabel))
        XCTAssertTrue(label.contains(AvailabilityToken.laundry.accessibilityName))
        XCTAssertFalse(label.contains("LAUNDRY"))
        XCTAssertFalse(label.contains("BOTTOM"))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(label))
    }

    func testSubmitAccessibilityLabelIncludesEmptyWhy() {
        XCTAssertEqual(
            DailyWearCopy.submitAccessibilityLabel(isCorrection: false, selectionEmpty: true),
            "\(DailyWearCopy.logSelected). \(DailyWearCopy.emptySelection)"
        )
        XCTAssertEqual(
            DailyWearCopy.submitAccessibilityLabel(isCorrection: true, selectionEmpty: false),
            DailyWearCopy.updateSelected
        )
        XCTAssertFalse(
            DailyWearCopy.containsMachineToken(
                DailyWearCopy.submitAccessibilityLabel(isCorrection: true, selectionEmpty: true)
            )
        )
    }
}
