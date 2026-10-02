import Foundation

/// User-facing copy for the Sprint 9 wear calendar (#123). No machine tokens.
enum WearCalendarCopy {
    static let title = "Calendar"
    static let today = "Today"
    static let todayHint = "Shows this month and selects today."
    static let previousMonth = "Previous month"
    static let nextMonth = "Next month"
    static let noOutfitRecorded = "No outfit recorded"
    static let noOutfitHint = "Log what you wear from the Outfit tab. Browsing the calendar never creates an outfit."
    static let historyNote = "Shows the pieces you logged, with their current names and photos."
    static let openGarmentHint = "Opens this piece in your wardrobe."
    static let multipleLooksNote = "More than one look was recorded on this day."

    static func loggedAt(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return "Logged at \(date.formatted(style))"
    }

    static func missingItems(_ count: Int) -> String {
        count == 1
            ? "1 piece is no longer in your wardrobe"
            : "\(count) pieces are no longer in your wardrobe"
    }

    static func monthTitle(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle().month(.wide).year()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    static func dayTitle(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .complete, time: .omitted)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    static func dayAccessibility(
        _ date: Date,
        hasRecord: Bool,
        isToday: Bool,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        var parts = [date.formatted(style)]
        if isToday { parts.append("Today") }
        parts.append(hasRecord ? "Outfit recorded" : noOutfitRecorded)
        return parts.joined(separator: ", ")
    }
}
