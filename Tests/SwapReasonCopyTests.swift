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

    func testDeviceAccessCopyMatchesSpec() {
        XCTAssertEqual(DressingCopy.deviceAccessRejectedTitle, "This phone isn't authorized")
        XCTAssertEqual(
            DressingCopy.deviceAccessRejectedNoOutfit,
            "New outfits can't load until device access is set up again. Your wardrobe is safe on this phone."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessRejectedWithOutfit,
            "Showing your previous outfit. New outfits and swaps can't load until device access is set up again."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessRejectedSwap,
            "Swaps can't load until device access is set up again. Your outfit hasn't changed."
        )
        XCTAssertEqual(DressingCopy.deviceAccessSetUpAction, "Set up device access")
        XCTAssertEqual(DressingCopy.deviceAccessRequiredHint, "Set up device access first.")
        XCTAssertEqual(DressingCopy.deviceAccessNotAccepted, "Device access: not accepted")
        XCTAssertEqual(
            DressingCopy.deviceAccessNotAcceptedHelp,
            "This phone's access wasn't accepted. Enroll again with your enrollment secret."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessAskOwner,
            "If you didn't set up this app, ask the person who did."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessModeHelpSecret,
            "Use this to set up a phone. The app gets its own access from it."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessModeHelpToken,
            "Only for access this app already issued. Most people should use Enrollment secret."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessWrongShape,
            "That doesn't look like a device token. If it's an enrollment secret, choose Enrollment secret and paste it there."
        )
        XCTAssertEqual(
            DressingCopy.deviceAccessEnrollSuccessAnnouncement,
            "Device access set up. New outfits can load again."
        )
    }

    func testEmptyAndOversizedReasonsRemainBounded() {
        XCTAssertEqual(DressingCopy.humanReason("  "), "Works with the pieces you’re keeping.")
        for suffix in ["", "."] {
            XCTAssertLessThanOrEqual(DressingCopy.humanReason(String(repeating: "long phrase ", count: 30) + suffix).count, 120)
        }
    }
}
