import Foundation

/// Sprint 9 (#124, ADR-0004) — bottom tabs: Wardrobe, Outfit, Calendar, Profile.
enum AppTab: Hashable, Sendable {
    case wardrobe
    case outfit
    case calendar
    case profile
}

/// Pure tab-change policy so every tab switch is decided in one testable place.
enum TabNavigation {
    enum Decision: Equatable {
        /// Already there.
        case none
        case select(AppTab)
        /// Profile has unsaved edits: ask Save / Discard / Keep editing, then go to the tab.
        case askToSaveProfile(then: AppTab)
        /// Opening Outfit while picking a starting item means "Return to outfit".
        case returnToOutfit
    }

    static func decide(
        from current: AppTab,
        to requested: AppTab,
        profileHasUnsavedChanges: Bool,
        isPickingStartingItem: Bool
    ) -> Decision {
        guard requested != current else { return .none }
        if current == .profile && profileHasUnsavedChanges {
            return .askToSaveProfile(then: requested)
        }
        if requested == .outfit && isPickingStartingItem {
            return .returnToOutfit
        }
        return .select(requested)
    }
}
