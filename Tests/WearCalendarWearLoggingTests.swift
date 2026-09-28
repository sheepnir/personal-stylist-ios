import XCTest
@testable import PersonalStylist

/// Sprint 9 (#123) — the calendar agrees with the existing one-look-per-day `WearLogging`
/// rules: confirm, duplicate confirm, replacement, Undo, counts, and later board changes.
final class WearCalendarWearLoggingTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func at(_ hour: Int, day: Int = 28) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private var day28: WearCalendar.Day { .init(year: 2026, month: 9, day: 28) }

    func testConfirmReplaceAndUndoMatchCalendarAndCounts() throws {
        let a = UUID(), b = UUID(), c = UUID()
        var events: [StubWearEvent] = []

        let first = WearLogging.confirm(existing: events, garmentIds: [a, b], wornOn: at(8), sourceOutfitId: nil, calendar: cal)
        events.append(try XCTUnwrap(first.event))
        XCTAssertEqual(WearCalendar.records(on: day28, events: events, calendar: cal).map(\.garmentIds), [[a, b]])

        let duplicate = WearLogging.confirm(existing: events, garmentIds: [b, a], wornOn: at(9), sourceOutfitId: nil, calendar: cal)
        XCTAssertFalse(duplicate.didWrite)
        XCTAssertEqual(WearCalendar.records(on: day28, events: events, calendar: cal).count, 1)

        let replace = WearLogging.confirm(existing: events, garmentIds: [a, c], wornOn: at(10), sourceOutfitId: nil, calendar: cal)
        events = apply(replace.voided, to: events) + [try XCTUnwrap(replace.event)]
        XCTAssertEqual(WearCalendar.records(on: day28, events: events, calendar: cal).map(\.garmentIds), [[a, c]])
        XCTAssertEqual(WearLogging.counts(from: events)[b], nil)

        let undo = try XCTUnwrap(WearLogging.undoToday(events: events, now: at(11), calendar: cal))
        events = apply(undo.updated, to: events)
        XCTAssertEqual(WearCalendar.records(on: day28, events: events, calendar: cal).map(\.garmentIds), [[a, b]],
                       "Undo restores the replaced look on the calendar")
        let counts = WearLogging.counts(from: events)
        let shownIds = WearCalendar.records(on: day28, events: events, calendar: cal).flatMap(\.garmentIds)
        XCTAssertEqual(Set(counts.keys), Set(shownIds), "calendar and counts use the same active events")
    }

    func testCalendarAgreesWithActiveSameDay() {
        var events: [StubWearEvent] = []
        for hour in [0, 7, 13, 23] {
            events.append(StubWearEvent(id: UUID(), garmentIds: [UUID()], wornOn: at(hour)))
            events.append(StubWearEvent(id: UUID(), garmentIds: [UUID()], wornOn: at(hour, day: 29)))
        }
        events.append(StubWearEvent(id: UUID(), garmentIds: [UUID()], wornOn: at(12), voidedAt: at(12)))
        for probe in [at(0), at(12), at(23, day: 29)] {
            let expected = Set(WearLogging.activeSameDay(events: events, day: probe, calendar: cal).map(\.id))
            let shown = Set(WearCalendar.records(on: WearCalendar.day(for: probe, calendar: cal), events: events, calendar: cal).map(\.id))
            XCTAssertEqual(shown, expected)
        }
    }

    private func apply(_ updates: [StubWearEvent], to events: [StubWearEvent]) -> [StubWearEvent] {
        var byId = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        for update in updates { byId[update.id] = update }
        return events.map { byId[$0.id]! }
    }
}
