import XCTest
@testable import EasyTODO

final class SchoolCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    func testNormalWeekdayUsesItsTimetableAndPeriodOrder() throws {
        let day = try XCTUnwrap(SchoolCalendar.semester1.day(on: date(2026, 10, 12), timetable: .semester1, calendar: calendar))
        XCTAssertEqual(day.status, .regularSchoolDay)
        XCTAssertEqual(day.lessons?.map(\.course), ["Lit", "Research", "CM"])
        XCTAssertEqual(day.lessons?.map(\.period), [1, 4, 5])
    }

    func testConfirmedLunchPlacementAndFridayWeekendTimetables() {
        let timetable = SchoolTimetable.semester1
        XCTAssertEqual(timetable.lessons(on: .tuesday).filter { $0.session == .beforeLunch }.map(\.course), ["Adv.Math", "Lit", "PE"])
        XCTAssertEqual(timetable.lessons(on: .tuesday).filter { $0.session == .afterLunch }.map(\.course), ["Man"])
        XCTAssertEqual(timetable.lessons(on: .wednesday).filter { $0.session == .beforeLunch }.map(\.course), ["Adv.Math", "Psy"])
        XCTAssertEqual(timetable.lessons(on: .wednesday).filter { $0.session == .afterLunch }.map(\.course), ["Research"])
        XCTAssertEqual(timetable.lessons(on: .thursday).map(\.period), [1, 3])
        for day in [SchoolWeekday.friday, .saturday, .sunday] {
            XCTAssertTrue(timetable.lessons(on: day).isEmpty)
        }
        XCTAssertEqual(SchoolCalendar.semester1.day(on: date(2026, 10, 9), timetable: timetable, calendar: calendar)?.status, .regularSchoolDay)
    }

    func testNoSchoolSuppressesClasses() {
        let day = SchoolCalendar.semester1.day(on: date(2026, 11, 11), timetable: .semester1, calendar: calendar)
        XCTAssertEqual(day?.status, .noSchool)
        XCTAssertEqual(day?.lessons, [])
    }

    func testOctober10UsesWednesdayTimetableIncludingAfterLunchResearch() {
        let day = SchoolCalendar.semester1.day(on: date(2026, 10, 10), timetable: .semester1, calendar: calendar)
        XCTAssertEqual(day?.status, .replacementSchoolDay(.wednesday))
        XCTAssertEqual(day?.lessons, SchoolTimetable.semester1.lessons(on: .wednesday))
    }

    func testPendingRemainsUnresolvedUntilAnExplicitResolution() {
        var school = SchoolCalendar.semester1
        let key = SchoolDate(2026, 10, 12)
        school.overrides[key] = .pending
        let pending = school.day(on: date(2026, 10, 12), timetable: .semester1, calendar: calendar)
        XCTAssertEqual(pending?.status, .pending)
        XCTAssertNil(pending?.lessons)
        school.resolve(key, as: .normalSchool)
        XCTAssertEqual(school.day(on: date(2026, 10, 12), timetable: .semester1, calendar: calendar)?.lessons?.count, 3)
        school.resolve(key, as: .noSchool)
        XCTAssertEqual(school.day(on: date(2026, 10, 12), timetable: .semester1, calendar: calendar)?.lessons, [])
        school.resolve(key, as: .useTimetable(.thursday))
        XCTAssertEqual(school.day(on: date(2026, 10, 12), timetable: .semester1, calendar: calendar)?.lessons?.map(\.course), ["Psy", "PE"])
    }

    func testHolidayRangesAreInclusiveAndSuppressClasses() {
        let dates = [SchoolDate(2026, 9, 29), SchoolDate(2026, 9, 30), SchoolDate(2026, 10, 30), SchoolDate(2026, 11, 11)]
            + (1...6).map { SchoolDate(2026, 10, $0) }
            + (14...18).map { SchoolDate(2026, 12, $0) }
            + (21...25).map { SchoolDate(2026, 12, $0) }
            + (25...31).map { SchoolDate(2027, 1, $0) }
        for key in dates {
            let day = SchoolCalendar.semester1.day(on: key.date(in: calendar)!, timetable: .semester1, calendar: calendar)
            XCTAssertEqual(day?.status, .noSchool, key.id)
            XCTAssertEqual(day?.lessons, [], key.id)
        }
        for key in [SchoolDate(2026, 9, 28), SchoolDate(2026, 10, 7), SchoolDate(2026, 12, 28), SchoolDate(2027, 1, 22)] {
            XCTAssertEqual(SchoolCalendar.semester1.day(on: key.date(in: calendar)!, timetable: .semester1, calendar: calendar)?.status, .regularSchoolDay)
        }
        XCTAssertFalse(SchoolCalendar.semester1.overrides.values.contains(.pending))
    }

    func testExplicitSemesterEndDoesNotInventNextSemesterStatus() {
        var school = SchoolCalendar.semester1
        school.semesterEnd = SchoolDate(2027, 2, 1)
        XCTAssertNil(school.day(on: date(2027, 2, 2), timetable: .semester1, calendar: calendar))
    }

    func testSpecialEventsStayVisibleOnNoSchoolDaysAndDoNotChangeSchoolStatus() {
        let event = event(start: date(2026, 10, 1, 10), end: date(2026, 10, 1, 11))
        let schedule = schedule(on: date(2026, 10, 1), events: [event])
        let day = schedule.days[4]
        XCTAssertEqual(day.school?.status, .noSchool)
        XCTAssertEqual(day.school?.lessons, [])
        XCTAssertEqual(day.events.map(\.id), [event.id])
        let regular = self.schedule(on: date(2026, 10, 12), events: [self.event(start: date(2026, 10, 12), end: date(2026, 10, 13), allDay: true)])
        XCTAssertEqual(regular.days[1].school?.status, .regularSchoolDay)
        XCTAssertEqual(regular.days[1].school?.lessons?.count, 3)
    }

    func testLunchBandExpandsAcrossWeekOnlyForLunchEvents() {
        // These are test fixture hours, not seeded school bell times.
        let lunch = SchoolLunchWindow(startMinute: 12 * 60, endMinute: 13 * 60)!
        let lunchtime = event(start: date(2026, 10, 12, 12), end: date(2026, 10, 12, 13))
        let schedule = schedule(on: date(2026, 10, 12), events: [lunchtime], lunch: lunch)
        XCTAssertTrue(schedule.expandsLunch)
        XCTAssertEqual(schedule.events(on: schedule.days[1], in: .lunch).count, 1)
        XCTAssertTrue(schedule.events(on: schedule.days[2], in: .lunch).isEmpty)
        XCTAssertFalse(self.schedule(on: date(2026, 10, 12), events: [], lunch: lunch).expandsLunch)
        let before = event(start: date(2026, 10, 12, 11), end: date(2026, 10, 12, 12))
        let after = event(start: date(2026, 10, 12, 13), end: date(2026, 10, 12, 14))
        let allDay = event(start: date(2026, 10, 12), end: date(2026, 10, 13), allDay: true)
        let other = self.schedule(on: date(2026, 10, 12), events: [before, after, allDay], lunch: lunch)
        XCTAssertFalse(other.expandsLunch)
        XCTAssertEqual(other.events(on: other.days[1], in: .beforeLunch).map(\.id), [before.id])
        XCTAssertEqual(other.events(on: other.days[1], in: .afterLunch).map(\.id), [after.id])
        XCTAssertEqual(other.events(on: other.days[1], in: .unplaced).map(\.id), [allDay.id])
    }

    func testUnknownLunchHoursDoNotGuessAndExplicitLunchPlacementWorks() throws {
        let event = event(start: date(2026, 10, 12, 12), end: date(2026, 10, 12, 13))
        let key = try XCTUnwrap(event.mappingKey)
        XCTAssertFalse(schedule(on: date(2026, 10, 12), events: [event]).expandsLunch)
        let placed = schedule(on: date(2026, 10, 12), events: [event], placements: [key: .lunch])
        XCTAssertTrue(placed.expandsLunch)
    }

    func testSundayWeekCrossesMonthAndYearRegardlessOfLocaleFirstWeekday() {
        var calendar = calendar
        calendar.firstWeekday = 2
        let week = CalendarWeek(containing: date(2027, 1, 1), calendar: calendar)
        XCTAssertEqual(week.days.first, date(2026, 12, 27))
        XCTAssertEqual(week.days.last, date(2027, 1, 2))
        XCTAssertEqual(week.interval.end, date(2027, 1, 3))
        XCTAssertEqual(week.days.count, 7)
    }

    func testWeekUsesCalendarArithmeticAcrossDST() {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (month, day, hours) in [(3, 8, 167), (11, 1, 169)] {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let week = CalendarWeek(containing: date, calendar: calendar)
            XCTAssertEqual(week.interval.duration, Double(hours * 3600))
            XCTAssertTrue(week.days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        }
    }

    func testPendingWarningContainsOnlyExplicitPendingDates() {
        var school = SchoolCalendar.semester1
        school.overrides[SchoolDate(2026, 10, 12)] = .pending
        let schedule = WeeklySchoolSchedule(week: CalendarWeek(containing: date(2026, 10, 12), calendar: calendar),
                                           school: school, timetable: .semester1, events: [], calendar: calendar,
                                           lunchWindow: nil, placements: [:])
        XCTAssertEqual(schedule.pendingDates, [SchoolDate(2026, 10, 12)])
    }

    func testEventMappingDistinguishesOccurrencesAndCalendars() {
        let first = event(start: date(2026, 10, 12, 12), end: date(2026, 10, 12, 13))
        var second = first
        second.calendarIdentifier = "another-calendar"
        XCTAssertNotEqual(first.mappingKey, second.mappingKey)
        second = first
        second.occurrenceStart = date(2026, 10, 13, 12)
        XCTAssertNotEqual(first.mappingKey, second.mappingKey)
    }

    func testUpcomingPendingQueryExcludesPastDistantAndOutOfSemesterDates() {
        var school = SchoolCalendar.semester1
        for day in [1, 12, 20, 30] { school.overrides[SchoolDate(2026, 10, day)] = .pending }
        school.semesterEnd = SchoolDate(2026, 10, 19)
        XCTAssertEqual(school.pendingDates(from: SchoolDate(2026, 10, 10), through: SchoolDate(2026, 10, 24)),
                       [SchoolDate(2026, 10, 12)])
    }

    func testEventSpanningLunchExpandsBandButExactEndBoundaryDoesNot() {
        let lunch = SchoolLunchWindow(startMinute: 720, endMinute: 780)!
        let spanning = event(start: date(2026, 10, 12, 11), end: date(2026, 10, 12, 14))
        XCTAssertTrue(schedule(on: date(2026, 10, 12), events: [spanning], lunch: lunch).expandsLunch)
        let instant = event(start: date(2026, 10, 12, 12), end: date(2026, 10, 12, 12))
        XCTAssertTrue(schedule(on: date(2026, 10, 12), events: [instant], lunch: lunch).expandsLunch)
        XCTAssertNil(SchoolLunchWindow(startMinute: 780, endMinute: 720))
    }

    private func schedule(on date: Date, events: [CalendarGlanceEvent], lunch: SchoolLunchWindow? = nil,
                          placements: [String: SpecialEventBand] = [:]) -> WeeklySchoolSchedule {
        WeeklySchoolSchedule(week: CalendarWeek(containing: date, calendar: calendar), school: .semester1,
                             timetable: .semester1, events: events, calendar: calendar,
                             lunchWindow: lunch, placements: placements)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func event(start: Date, end: Date, allDay: Bool = false) -> CalendarGlanceEvent {
        CalendarGlanceEvent(id: UUID(), title: "Special event", start: start, end: end, isAllDay: allDay,
                           calendarTitle: "Test", calendarIdentifier: "calendar", eventIdentifier: "event")
    }
}
