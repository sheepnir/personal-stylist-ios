import XCTest

final class WardrobeCardInteractionTests: XCTestCase {
    @MainActor
    func testCardLowerAreaOpensDetailAndLongPressUsesOnlyContextMenu() {
        let app = XCUIApplication()
        app.launch()
        let tip = app.buttons["Got it"]
        if tip.waitForExistence(timeout: 3) { tip.tap() }
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "wardrobe.card.")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
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
