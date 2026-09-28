import XCTest
@testable import PersonalStylist

/// Sprint 9 (#124) — every tab change goes through one policy.
final class TabNavigationTests: XCTestCase {
    private func decide(_ from: AppTab, _ to: AppTab, dirty: Bool = false, picking: Bool = false) -> TabNavigation.Decision {
        TabNavigation.decide(from: from, to: to, profileHasUnsavedChanges: dirty, isPickingStartingItem: picking)
    }

    func testPlainSwitchesSelectTheTab() {
        XCTAssertEqual(decide(.wardrobe, .calendar), .select(.calendar))
        XCTAssertEqual(decide(.outfit, .profile), .select(.profile))
        XCTAssertEqual(decide(.calendar, .calendar), .none)
    }

    func testLeavingProfileWithUnsavedEditsAsksFirst() {
        for target in [AppTab.wardrobe, .outfit, .calendar] {
            XCTAssertEqual(decide(.profile, target, dirty: true), .askToSaveProfile(then: target))
        }
        XCTAssertEqual(decide(.profile, .profile, dirty: true), .none)
        XCTAssertEqual(decide(.profile, .wardrobe, dirty: false), .select(.wardrobe))
        XCTAssertEqual(decide(.wardrobe, .profile, dirty: true), .select(.profile),
                       "only leaving Profile is guarded")
    }

    func testOpeningOutfitWhilePickingReturnsToOutfit() {
        XCTAssertEqual(decide(.wardrobe, .outfit, picking: true), .returnToOutfit)
        XCTAssertEqual(decide(.wardrobe, .calendar, picking: true), .select(.calendar))
        XCTAssertEqual(decide(.profile, .outfit, dirty: true, picking: true), .askToSaveProfile(then: .outfit),
                       "the profile guard runs first; the chosen tab is re-evaluated afterwards")
    }
}
