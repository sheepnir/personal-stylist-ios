import XCTest

final class WardrobeCardInteractionTests: XCTestCase {
    /// Run only on a dedicated fresh Simulator. Semantic/layout checks do not
    /// replace a physical VoiceOver focus walk or phone Dynamic Type acceptance.
    @MainActor
    func testCalendarLargestTextExposesSelectableFullDateTargetsWithoutCreatingOutfit() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let tip = app.buttons["Got it"]
        if tip.waitForExistence(timeout: 3) { tip.tap() }

        app.tabBars.buttons["Outfit"].tap()
        XCTAssertTrue(app.staticTexts["No outfit yet"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.previousMonth"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["calendar.empty"].exists
                      || app.staticTexts["No outfit recorded"].exists)

        // AX rows carry full dates, unlike the compact grid's numeric visible labels.
        // Choose visible rows so this checks real tap targets, not offscreen frames.
        let days = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "No outfit recorded"))
        var visibleDays = days.allElementsBoundByIndex.filter { $0.isHittable && !$0.isSelected }
        for _ in 0..<4 where visibleDays.count < 2 {
            app.scrollViews.firstMatch.swipeUp()
            visibleDays = days.allElementsBoundByIndex.filter { $0.isHittable && !$0.isSelected }
        }
        XCTAssertGreaterThanOrEqual(visibleDays.count, 2, "AX date list must expose multiple usable date rows")
        guard visibleDays.count >= 2 else { return }
        let first = visibleDays[0]
        let second = visibleDays[1]
        let firstLabel = first.label
        let secondLabel = second.label
        XCTAssertTrue(firstLabel.contains(", 20"), "Date target must speak a full date including year")
        XCTAssertGreaterThanOrEqual(first.frame.width, 44)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertGreaterThanOrEqual(second.frame.width, 44)
        XCTAssertGreaterThanOrEqual(second.frame.height, 44)
        XCTAssertFalse(first.frame.intersects(second.frame), "Date targets must remain separate")

        first.tap()
        let firstAfter = app.buttons[firstLabel]
        XCTAssertTrue(firstAfter.isSelected, "Date selection must expose its selected trait")
        let secondAfter = app.buttons[secondLabel]
        XCTAssertTrue(secondAfter.isHittable)
        secondAfter.tap()
        XCTAssertTrue(app.buttons[secondLabel].isSelected)
        XCTAssertFalse(app.buttons[firstLabel].isSelected)

        // Navigation is read-only. Returning to Today and another tab must not
        // create an outfit or a wear record on this fresh synthetic installation.
        let nextMonth = app.buttons["calendar.nextMonth"]
        for _ in 0..<4 where !nextMonth.isHittable {
            app.scrollViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(nextMonth.isHittable)
        nextMonth.tap()
        XCTAssertTrue(app.otherElements["calendar.empty"].exists
                      || app.staticTexts["No outfit recorded"].exists)
        app.buttons["calendar.today"].tap()
        XCTAssertTrue(app.otherElements["calendar.empty"].exists
                      || app.staticTexts["No outfit recorded"].exists)
        app.tabBars.buttons["Outfit"].tap()
        XCTAssertTrue(app.staticTexts["No outfit yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardLowerAreaOpensDetailAndLongPressUsesOnlyContextMenu() {
        let app = XCUIApplication()
        app.launch()
        let tip = app.buttons["Got it"]
        if tip.waitForExistence(timeout: 3) { tip.tap() }
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wardrobe.card.")).firstMatch
        if !card.waitForExistence(timeout: 2) {
            // Fresh installs intentionally have no seeded wardrobe. Add one
            // synthetic piece through the same sample intake and Save UI as a user.
            let add = app.buttons["Add your first piece"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            guard add.exists else { return }
            add.tap()
            let samples = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Use a sample piece")).firstMatch
            XCTAssertTrue(samples.waitForExistence(timeout: 5))
            guard samples.exists else { return }
            samples.tap()
            XCTAssertTrue(app.navigationBars["Use a sample piece"].waitForExistence(timeout: 5))
            let sampleButtons = app.scrollViews.buttons
            XCTAssertTrue(sampleButtons.firstMatch.waitForExistence(timeout: 5))
            let sample = sampleButtons.allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(sample, "Sample picker must expose a usable synthetic garment")
            guard let sample else { return }
            sample.tap()
            let save = app.buttons["finish.details.save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            guard save.exists else { return }
            XCTAssertTrue(save.isEnabled, "Synthetic sample must arrive ready for explicit Save")
            guard save.isEnabled else { return }
            save.tap()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        guard card.exists else { return }
        let name = String(card.label.split(separator: ",").first!)
        // Name/badge area used to sit outside the image's tap target.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 1.2)
        let open = app.buttons["Open garment"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Open garment").count, 1)
        XCTAssertFalse(app.navigationBars["Availability"].exists)
        XCTAssertFalse(app.buttons["Cycle to next state"].exists)
        open.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }
}
