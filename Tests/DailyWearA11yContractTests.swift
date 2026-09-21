import XCTest
@testable import PersonalStylist

/// #280 wear a11y contracts. Traits and spoken strings — not colour alone, no machine tokens.
final class DailyWearA11yContractTests: XCTestCase {
    func testPickerRowUsesSelectedTraitStringsAndAvailabilityName() {
        var laundry = garment("Ink Trousers", slot: .bottom)
        laundry.availability = "LAUNDRY"
        let shirt = garment("Navy Oxford Shirt", slot: .top)

        XCTAssertEqual(
            DailyWearCopy.pickerRowLabel(shirt),
            "Navy Oxford Shirt, Top, Available"
        )
        XCTAssertEqual(
            DailyWearCopy.pickerRowLabel(laundry),
            "Ink Trousers, Bottom, In laundry"
        )
        XCTAssertEqual(DailyWearCopy.selectedValue, "Selected")
        XCTAssertEqual(DailyWearCopy.notSelectedValue, "Not selected")
        XCTAssertFalse(DailyWearCopy.containsMachineToken(DailyWearCopy.pickerRowLabel(laundry)))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(DailyWearCopy.selectedValue))
    }

    func testDisabledSubmitAndBoardWhyStayHuman() {
        XCTAssertTrue(
            DailyWearCopy.submitAccessibilityLabel(isCorrection: false, selectionEmpty: true)
                .contains(DailyWearCopy.emptySelection)
        )
        XCTAssertEqual(
            DailyWearCopy.submitAccessibilityLabel(isCorrection: true, selectionEmpty: false),
            DailyWearCopy.updateSelected
        )

        let wearing = DailyWearBoardPrimary.wearingThis
        XCTAssertEqual(wearing.title, DailyWearCopy.wearingThis)
        XCTAssertEqual(wearing.accessibilityHint, DailyWearCopy.submitHintNew)
        let change = DailyWearBoardPrimary.changeWhatIWore
        XCTAssertEqual(change.title, DailyWearCopy.changeWhatIWore)
        XCTAssertEqual(change.accessibilityHint, DailyWearCopy.submitHintCorrection)
        XCTAssertFalse(DailyWearCopy.containsMachineToken(wearing.accessibilityHint))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(change.accessibilityHint))
    }

    func testLoggedTodayAndFailureCopyHaveNoTokens() {
        let wornOn = Date(timeIntervalSince1970: 1_726_920_000)
        let ax = DailyWearCopy.rowAccessibility(
            leadName: "Navy Oxford Shirt",
            extraCount: 1,
            wornOn: wornOn,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertTrue(ax.contains(DailyWearCopy.loggedToday))
        XCTAssertTrue(ax.contains(DailyWearCopy.changeWhatIWore))
        XCTAssertTrue(ax.contains("Wearing this is off"))
        XCTAssertEqual(DailyWearCopy.loggedTodayHint, "Shows today’s logged outfit. Wearing this is turned off.")
        XCTAssertEqual(DailyWearCopy.persistFailedHint, "Today’s wear was not saved. Try again.")
        XCTAssertFalse(DailyWearCopy.containsMachineToken(ax))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(DailyWearCopy.persistFailed))
        XCTAssertFalse(DailyWearCopy.containsMachineToken(DailyWearCopy.replacingSession))
    }

    private func garment(_ name: String, slot: StubSlot) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
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
    }
}
