import Foundation

/// Sprint 9 wear calendar (#123, ADR-0004) — pure, read-only views over recorded wear events.
///
/// Days use the same local-calendar rule as `WearLogging` (`isDate(_:inSameDayAs:)`) and the
/// daily-wear fetch (`startOfDay`): an event belongs to the local date its `wornOn` falls on
/// in the injected calendar/time zone. Stored `wornOn` values are never rewritten. Voided
/// events are excluded; nothing here writes, generates or calls a model.
enum WearCalendar {
    /// A local calendar date, independent of time of day and DST offsets.
    struct Day: Hashable, Comparable, Sendable {
        let year: Int
        let month: Int
        let day: Int

        static func < (lhs: Day, rhs: Day) -> Bool {
            (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
        }
    }

    /// One month page: `leadingBlanks` empty cells, then `dayCount` days starting on day 1.
    struct Month: Hashable, Sendable {
        let year: Int
        let month: Int
        let leadingBlanks: Int
        let dayCount: Int

        var days: [Day] { (1...max(1, dayCount)).map { Day(year: year, month: month, day: $0) } }
    }

    static func day(for date: Date, calendar: Calendar) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
    }

    /// Start of `day` in `calendar`. On a DST gap at midnight this is the first valid instant.
    static func startDate(of day: Day, calendar: Calendar) -> Date? {
        guard let noon = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else {
            return nil
        }
        return calendar.startOfDay(for: noon)
    }

    /// Active events grouped by local day, each day newest first, then by `id` (stable).
    static func activeEventsByDay(_ events: [StubWearEvent], calendar: Calendar) -> [Day: [StubWearEvent]] {
        var grouped: [Day: [StubWearEvent]] = [:]
        for event in events where !event.isVoided {
            grouped[day(for: event.wornOn, calendar: calendar), default: []].append(event)
        }
        return grouped.mapValues(orderedNewestFirst)
    }

    /// Active records for one local day. Legacy days may hold several; all are returned.
    static func records(on day: Day, events: [StubWearEvent], calendar: Calendar) -> [StubWearEvent] {
        orderedNewestFirst(events.filter { !$0.isVoided && Self.day(for: $0.wornOn, calendar: calendar) == day })
    }

    /// Days in `month` that have at least one active record.
    static func markedDays(in month: Month, events: [StubWearEvent], calendar: Calendar) -> Set<Day> {
        var marked = Set<Day>()
        for event in events where !event.isVoided {
            let d = day(for: event.wornOn, calendar: calendar)
            if d.year == month.year && d.month == month.month { marked.insert(d) }
        }
        return marked
    }

    /// Month page containing `date`, honoring the calendar's `firstWeekday`.
    static func month(containing date: Date, calendar: Calendar) -> Month {
        let d = day(for: date, calendar: calendar)
        return month(year: d.year, month: d.month, calendar: calendar)
    }

    static func month(year: Int, month: Int, calendar: Calendar) -> Month {
        let first = Day(year: year, month: month, day: 1)
        guard let start = startDate(of: first, calendar: calendar) else {
            return Month(year: year, month: month, leadingBlanks: 0, dayCount: 30)
        }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        return Month(year: year, month: month, leadingBlanks: leading, dayCount: count)
    }

    /// The month `offset` months away from `month` (negative for earlier).
    static func month(_ month: Month, offsetBy offset: Int, calendar: Calendar) -> Month {
        let zeroBased = month.year * 12 + (month.month - 1) + offset
        let year = Int((Double(zeroBased) / 12).rounded(.down))
        let monthIndex = zeroBased - year * 12 + 1
        return self.month(year: year, month: monthIndex, calendar: calendar)
    }

    /// Short weekday symbols rotated so the calendar's first weekday comes first.
    static func orderedWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Full weekday names in the same order, for VoiceOver.
    static func orderedWeekdayNames(calendar: Calendar) -> [String] {
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Garments of one record, split into those still in the wardrobe (event order) and the
    /// count no longer available. Never substitutes a different garment.
    static func resolve<G>(
        _ event: StubWearEvent,
        garments: [G],
        id: (G) -> UUID
    ) -> (available: [G], missingCount: Int) {
        var byId: [UUID: G] = [:]
        for garment in garments { byId[id(garment)] = garment }
        var available: [G] = []
        var missing = 0
        var seen = Set<UUID>()
        for gid in event.garmentIds where seen.insert(gid).inserted {
            if let garment = byId[gid] {
                available.append(garment)
            } else {
                missing += 1
            }
        }
        return (available, missing)
    }

    private static func orderedNewestFirst(_ events: [StubWearEvent]) -> [StubWearEvent] {
        events.sorted { lhs, rhs in
            if lhs.wornOn != rhs.wornOn { return lhs.wornOn > rhs.wornOn }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
