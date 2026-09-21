import Foundation

/// D-75 / #103 / #125 — daily wear picker, correction, and Logged today copy.
/// Human-readable only: no HTTP, URLs, machine enums, or persistence tokens.
enum DailyWearCopy {
    static let pickerTitle = "What did you wear?"
    static let wearingThis = "Wearing this"
    static let changeWhatIWore = "Change what I wore"
    static let useCorrectionInstead = "Today is already logged. Use Change what I wore."
    static let loggedToday = "Logged today"
    static let logSelected = "Log selected as worn"
    static let updateSelected = "Update what I wore"
    static let tryAgain = "Try again"
    static let done = "Done"
    static let cancel = "Cancel"

    static let newWearSubtitle = "Choose what you actually wore. Drafts need Finish details first."
    static let correctionSubtitle = "This replaces today’s log. Cancel leaves it as it is."
    static let emptyReady = "No ready garments yet. Finish details on a draft first."
    static let emptySelection = "Select at least one ready piece to log."
    static let emptySearch = "No ready garments match that search."
    static let notAvailableToday = "Not available today"
    static let searchPrompt = "Search garments"
    static let persistFailed = "Couldn’t save today’s wear. Try again."
    static let alreadyLogged = "Already logged today"
    static let blockedDrafts = "Finish details before logging wear."
    static let replacingSession = "Building a new look — today’s log stays saved."
    static let loggedTodayToast = "Logged for today"
    static let updatedTodayToast = "Updated today’s log"
    static let successTitle = "Logged for today"
    static let undoneTitle = "Wear undone"
    static let loggedAsWorn = "Logged as worn"
    static let returnToOutfit = "Return to outfit"

    static func loggedCount(_ n: Int) -> String {
        n == 1 ? "Logged 1 piece as worn." : "Logged \(n) pieces as worn."
    }

    static func timeOn(
        _ date: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func leadName(_ garments: [StubGarment]) -> String {
        garments.first?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? loggedToday
    }

    static func extraCount(total: Int) -> Int {
        max(0, total - 1)
    }

    static func rowTitle(leadName: String, extraCount: Int) -> String {
        let trimmed = leadName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? loggedToday : trimmed
        if extraCount <= 0 { return name }
        if extraCount == 1 { return "\(name) + 1 more" }
        return "\(name) + \(extraCount) more"
    }

    static func rowLine(
        leadName: String,
        extraCount: Int,
        wornOn: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        "\(rowTitle(leadName: leadName, extraCount: extraCount)) · \(timeOn(wornOn, locale: locale, calendar: calendar))"
    }

    static func rowAccessibility(
        leadName: String,
        extraCount: Int,
        wornOn: Date,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let title = rowTitle(leadName: leadName, extraCount: extraCount)
        return "\(loggedToday). \(title). Logged at \(timeOn(wornOn, locale: locale, calendar: calendar)). Opens today’s log. Wearing this is off. \(changeWhatIWore) is available."
    }

    static let loggedTodayHint = "Shows today’s logged outfit. Wearing this is turned off."
    static let searchHint = "Filters ready garments by name or slot"
    static let submitHintNew = "Logs the selected pieces as today’s wear"
    static let submitHintCorrection = "Replaces today’s log with the selected pieces"
    static let persistFailedHint = "Today’s wear was not saved. Try again."
    static let selectedValue = "Selected"
    static let notSelectedValue = "Not selected"

    static func pickerRowLabel(_ garment: StubGarment) -> String {
        "\(garment.displayName), \(garment.slot.displayLabel), \(garment.availabilityToken.accessibilityName)"
    }

    static func submitAccessibilityLabel(isCorrection: Bool, selectionEmpty: Bool) -> String {
        let title = isCorrection ? updateSelected : logSelected
        if selectionEmpty {
            return "\(title). \(emptySelection)"
        }
        return title
    }

    static func matchesSearch(_ garment: StubGarment, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        if garment.displayName.localizedCaseInsensitiveContains(needle) { return true }
        return garment.slot.displayLabel.localizedCaseInsensitiveContains(needle)
    }

    static func containsMachineToken(_ text: String) -> Bool {
        let forbidden = [
            "HTTP", "http://", "https://", "NSURL", "voidedAt", "WearEvent",
            "sourceOutfitId", "READY", "AVAILABLE", "token",
        ]
        return forbidden.contains { text.contains($0) }
    }
}
