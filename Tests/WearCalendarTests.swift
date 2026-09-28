import XCTest
@testable import PersonalStylist

/// Sprint 9 (#123) — pure wear-calendar grouping. Injected calendars and time zones only.
final class WearCalendarTests: XCTestCase {
    private func calendar(_ tz: String, firstWeekday: Int = 1) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func event(_ wornOn: Date, voided: Bool = false, id: UUID = UUID(), garments: [UUID] = [UUID()]) -> StubWearEvent {
        StubWearEvent(id: id, garmentIds: garments, wornOn: wornOn, voidedAt: voided ? wornOn : nil)
    }

    // MARK: - Local-day grouping

    func testMidnightSplitsDaysInLocalTime() {
        let cal = calendar("America/Los_Angeles")
        let late = event(date(cal, 2026, 9, 27, 23, 59))
        let early = event(date(cal, 2026, 9, 28, 0, 1))
        let grouped = WearCalendar.activeEventsByDay([late, early], calendar: cal)
        XCTAssertEqual(grouped[.init(year: 2026, month: 9, day: 27)]?.map(\.id), [late.id])
        XCTAssertEqual(grouped[.init(year: 2026, month: 9, day: 28)]?.map(\.id), [early.id])
    }

    func testTimeZoneChangeMovesDayWithoutRewritingStoredDate() {
        let la = calendar("America/Los_Angeles")
        let tokyo = calendar("Asia/Tokyo")
        let wornOn = date(la, 2026, 9, 27, 20, 0) // 2026-09-28 12:00 in Tokyo
        let ev = event(wornOn)
        XCTAssertEqual(WearCalendar.records(on: .init(year: 2026, month: 9, day: 27), events: [ev], calendar: la).map(\.id), [ev.id])
        XCTAssertEqual(WearCalendar.records(on: .init(year: 2026, month: 9, day: 28), events: [ev], calendar: tokyo).map(\.id), [ev.id])
        XCTAssertEqual(ev.wornOn, wornOn)
    }

    func testSpringForwardDayGroupsAndHasStart() {
        let ny = calendar("America/New_York")
        let before = event(date(ny, 2026, 3, 8, 1, 30))
        let after = event(date(ny, 2026, 3, 8, 3, 30))
        let day = WearCalendar.Day(year: 2026, month: 3, day: 8)
        XCTAssertEqual(Set(WearCalendar.records(on: day, events: [before, after], calendar: ny).map(\.id)), [before.id, after.id])
        XCTAssertNotNil(WearCalendar.startDate(of: day, calendar: ny))
        XCTAssertEqual(WearCalendar.month(year: 2026, month: 3, calendar: ny).dayCount, 31)
    }

    func testFallBackRepeatedHourStaysOnOneDay() {
        let ny = calendar("America/New_York")
        let firstPass = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
        let secondPass = firstPass.addingTimeInterval(3600) // 01:30 again, standard time
        let events = [event(firstPass), event(secondPass)]
        let day = WearCalendar.Day(year: 2026, month: 11, day: 1)
        XCTAssertEqual(WearCalendar.records(on: day, events: events, calendar: ny).count, 2)
        XCTAssertEqual(WearCalendar.records(on: day, events: events, calendar: ny).first?.wornOn, secondPass)
    }

    func testDSTGapAtMidnightStillYieldsADay() {
        // Santiago springs forward at 00:00 → 01:00 in early September.
        let santiago = calendar("America/Santiago")
        let day = WearCalendar.Day(year: 2026, month: 9, day: 6)
        let start = WearCalendar.startDate(of: day, calendar: santiago)
        XCTAssertNotNil(start)
        if let start {
            XCTAssertEqual(WearCalendar.day(for: start, calendar: santiago), day)
        }
    }

    // MARK: - Months

    func testLeapDayAndFebruaryLengths() {
        let utc = calendar("UTC")
        XCTAssertEqual(WearCalendar.month(year: 2028, month: 2, calendar: utc).dayCount, 29)
        XCTAssertEqual(WearCalendar.month(year: 2027, month: 2, calendar: utc).dayCount, 28)
        let leap = event(date(utc, 2028, 2, 29, 9))
        let feb = WearCalendar.month(year: 2028, month: 2, calendar: utc)
        XCTAssertEqual(WearCalendar.markedDays(in: feb, events: [leap], calendar: utc), [.init(year: 2028, month: 2, day: 29)])
    }

    func testMonthAndYearBoundaries() {
        let utc = calendar("UTC")
        let dec = WearCalendar.month(year: 2026, month: 12, calendar: utc)
        let jan = WearCalendar.month(dec, offsetBy: 1, calendar: utc)
        XCTAssertEqual([jan.year, jan.month], [2027, 1])
        let back = WearCalendar.month(jan, offsetBy: -1, calendar: utc)
        XCTAssertEqual([back.year, back.month], [2026, 12])
        let farBack = WearCalendar.month(jan, offsetBy: -13, calendar: utc)
        XCTAssertEqual([farBack.year, farBack.month], [2025, 12])
        let newYearsEve = event(date(utc, 2026, 12, 31, 23, 30))
        XCTAssertTrue(WearCalendar.markedDays(in: jan, events: [newYearsEve], calendar: utc).isEmpty)
        XCTAssertEqual(WearCalendar.markedDays(in: dec, events: [newYearsEve], calendar: utc).count, 1)
    }

    func testFirstWeekdayControlsLeadingBlanks() {
        // 1 September 2026 is a Tuesday.
        let sunday = WearCalendar.month(year: 2026, month: 9, calendar: calendar("UTC", firstWeekday: 1))
        let monday = WearCalendar.month(year: 2026, month: 9, calendar: calendar("UTC", firstWeekday: 2))
        XCTAssertEqual(sunday.leadingBlanks, 2)
        XCTAssertEqual(monday.leadingBlanks, 1)
        XCTAssertEqual(sunday.dayCount, 30)
        let symbols = WearCalendar.orderedWeekdaySymbols(calendar: calendar("UTC", firstWeekday: 2))
        XCTAssertEqual(symbols.count, 7)
        XCTAssertEqual(WearCalendar.orderedWeekdayNames(calendar: calendar("UTC", firstWeekday: 2)).first, "Monday")
    }

    // MARK: - Records

    func testVoidedEventsAreHiddenAndLegacyDaysAreDeterministic() {
        let utc = calendar("UTC")
        let voided = event(date(utc, 2026, 9, 10, 8), voided: true)
        let a = event(date(utc, 2026, 9, 10, 9), id: UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!)
        let b = event(date(utc, 2026, 9, 10, 9), id: UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!)
        let newest = event(date(utc, 2026, 9, 10, 18))
        let day = WearCalendar.Day(year: 2026, month: 9, day: 10)
        let shown = WearCalendar.records(on: day, events: [b, voided, newest, a], calendar: utc)
        XCTAssertEqual(shown.map(\.id), [newest.id, a.id, b.id])
        let onlyVoided = WearCalendar.records(on: day, events: [voided], calendar: utc)
        XCTAssertTrue(onlyVoided.isEmpty)
        let sep = WearCalendar.month(year: 2026, month: 9, calendar: utc)
        XCTAssertTrue(WearCalendar.markedDays(in: sep, events: [voided], calendar: utc).isEmpty)
    }

    func testResolveKeepsStoredMembershipAndCountsMissing() {
        struct G { let id: UUID; let name: String }
        let kept = G(id: UUID(), name: "a")
        let other = G(id: UUID(), name: "b")
        let deleted = UUID()
        let ev = event(Date(), garments: [other.id, deleted, kept.id, kept.id])
        let resolved = WearCalendar.resolve(ev, garments: [kept, other, G(id: UUID(), name: "unworn")], id: \.id)
        XCTAssertEqual(resolved.available.map(\.name), ["b", "a"], "stored order, no substitutes, no duplicates")
        XCTAssertEqual(resolved.missingCount, 1)
    }
}
