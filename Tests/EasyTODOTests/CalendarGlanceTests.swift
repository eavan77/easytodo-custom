import XCTest
@testable import EasyTODO

final class CalendarGlanceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    func testMidnightBoundariesAreExclusiveAndZeroDurationEventIsIncluded() throws {
        let endingAtToday = event("Yesterday", date(10, 1, 22), date(10, 2))
        let today = event("Today", date(10, 2, 23), date(10, 3))
        let tomorrow = event("Tomorrow", date(10, 3), date(10, 3))
        let outside = event("Outside", date(10, 4), date(10, 4, 1))
        let glance = CalendarEventSnapshot(range: DateInterval(start: date(10, 2), end: date(10, 4)),
                                       events: [outside, tomorrow, today, endingAtToday])
        XCTAssertEqual(glance.events(in: DateInterval(start: date(10, 2), end: date(10, 3))).map(\.title), ["Today"])
        XCTAssertEqual(glance.events(in: DateInterval(start: date(10, 3), end: date(10, 4))).map(\.title), ["Tomorrow"])
    }

    func testOvernightAndMultiDayAllDayEventsAppearOnBothDays() throws {
        let overnight = event("Overnight", date(10, 2, 23), date(10, 3, 2))
        let allDay = event("Holiday", date(10, 2), date(10, 4), allDay: true)
        let glance = CalendarEventSnapshot(range: DateInterval(start: date(10, 2), end: date(10, 4)),
                                       events: [overnight, allDay])
        for day in [DateInterval(start: date(10, 2), end: date(10, 3)), DateInterval(start: date(10, 3), end: date(10, 4))] {
            XCTAssertEqual(glance.events(in: day).map(\.title), ["Holiday", "Overnight"])
            XCTAssertTrue(glance.events(in: day)[0].isAllDay)
        }
    }

    func testAllDayEventDoesNotLeakIntoExclusiveEndDay() throws {
        let allDay = event("Holiday", date(10, 2), date(10, 3), allDay: true)
        let glance = CalendarEventSnapshot(range: DateInterval(start: date(10, 2), end: date(10, 4)), events: [allDay])
        XCTAssertEqual(glance.events(in: DateInterval(start: date(10, 2), end: date(10, 3))).count, 1)
        XCTAssertTrue(glance.events(in: DateInterval(start: date(10, 3), end: date(10, 4))).isEmpty)
    }

    func testEventsSortByStartAndPreserveSeparateRecurringOccurrences() throws {
        let late = event("Meeting", date(10, 2, 14), date(10, 2, 15))
        let early = event("Meeting", date(10, 2, 9), date(10, 2, 10))
        let glance = CalendarEventSnapshot(range: DateInterval(start: date(10, 2), end: date(10, 4)), events: [late, early])
        XCTAssertEqual(glance.events.map(\.id), [early.id, late.id])
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarGlanceEvent {
        CalendarGlanceEvent(id: UUID(), title: title, start: start, end: end,
                           isAllDay: allDay, calendarTitle: "Test calendar")
    }
}
