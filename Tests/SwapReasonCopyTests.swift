import XCTest
@testable import PersonalStylist

final class SwapReasonCopyTests: XCTestCase {
    func testLegacyFragmentsBecomeOneSentenceWithoutTitleCasingNames() {
        XCTAssertEqual(DressingCopy.humanReason("keeps the light_blue-and-tan pairing, and better for mild, and adds texture contrast"),
                       "Keeps the light blue-and-tan pairing, suits mild weather, and adds texture contrast.")
        XCTAssertEqual(DressingCopy.humanReason("works with Levi’s 501 jeans"), "Works with Levi’s 501 jeans.")
    }

    func testUpdatedServerCopyIsNotDoublePunctuated() {
        XCTAssertEqual(DressingCopy.humanReason("pairs Light blue with Sand, suits mild weather, and adds texture contrast."),
                       "Pairs Light blue with Sand, suits mild weather, and adds texture contrast.")
        XCTAssertEqual(DressingCopy.humanReason("pairs Light blue with Sand and suits mild weather."),
                       "Pairs Light blue with Sand and suits mild weather.")
    }

    func testEmptyAndOversizedReasonsRemainBounded() {
        XCTAssertEqual(DressingCopy.humanReason("  "), "Works with the pieces you’re keeping.")
        for suffix in ["", "."] {
            XCTAssertLessThanOrEqual(DressingCopy.humanReason(String(repeating: "long phrase ", count: 30) + suffix).count, 120)
        }
    }
}
