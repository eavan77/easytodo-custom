import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class CalendarSchoolDayHoverTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    func testHoverActionUsesBaseAndPersonalStatus() {
        for base in [SchoolDayStatus.regularSchoolDay, .replacementSchoolDay(.wednesday)] {
            XCTAssertEqual(CalendarSchoolDayHover.action(baseStatus: base, personalOverride: nil), .markNoSchool)
            XCTAssertEqual(CalendarSchoolDayHover.action(baseStatus: base, personalOverride: .noSchool), .restoreSchoolCalendar)
        }
        for base in [SchoolDayStatus.noSchool, .pending] {
            XCTAssertEqual(CalendarSchoolDayHover.action(baseStatus: base, personalOverride: nil), .none)
        }
        XCTAssertEqual(CalendarSchoolDayHover.action(baseStatus: nil, personalOverride: nil), .none)
        XCTAssertEqual(CalendarSchoolDayHoverAction.restoreSchoolCalendar.title, "Restore school calendar")
    }

    func testEnteringHeaderWithoutActionClearsPreviousAction() {
        let hover = CalendarSchoolDayHover()
        hover.headerEntered(date(12), action: .markNoSchool)
        XCTAssertEqual(hover.activeDate, date(12))
        hover.headerEntered(date(13), action: .none)
        XCTAssertNil(hover.activeDate)
    }

    func testWednesdayCanBeMarkedNoSchoolAndRestoredByHover() throws {
        try withStore { store, context in
            let date = date(14)
            let key = SchoolDate(date, calendar: calendar)
            let hover = CalendarSchoolDayHover()
            @MainActor func action() -> CalendarSchoolDayHoverAction {
                CalendarSchoolDayHover.action(for: date, in: store, calendar: calendar)
            }
            XCTAssertEqual(store.baseSchoolCalendar.effectiveSchoolStatus(for: date, calendar: calendar), .regularSchoolDay)
            XCTAssertNil(store.personalOverride(for: key))
            XCTAssertEqual(action(), .markNoSchool)
            hover.headerEntered(date, action: action())
            hover.performAction(in: store, calendar: calendar)
            XCTAssertEqual(store.effectiveSchoolStatus(for: date, calendar: calendar), .noSchool)
            XCTAssertEqual(action(), .restoreSchoolCalendar)
            XCTAssertEqual(store.schoolCalendar.day(on: date, timetable: store.preferences.timetable, calendar: calendar)?.lessons, [])
            hover.headerEntered(date, action: action())
            XCTAssertEqual(hover.activeDate, date)
            hover.performAction(in: store, calendar: calendar)
            XCTAssertNil(store.personalOverride(for: key))
            XCTAssertTrue(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).isEmpty)
            XCTAssertEqual(action(), .markNoSchool)
            XCTAssertEqual(store.effectiveSchoolStatus(for: date, calendar: calendar), .regularSchoolDay)
            XCTAssertEqual(store.schoolCalendar.day(on: date, timetable: store.preferences.timetable, calendar: calendar)?.lessons,
                           store.baseSchoolCalendar.day(on: date, timetable: store.preferences.timetable, calendar: calendar)?.lessons)
            XCTAssertEqual(store.schoolCalendar.day(on: date, timetable: store.preferences.timetable, calendar: calendar)?.lessons?.map(\.course), ["Adv.Math", "Psy", "Research"])
        }
    }

    func testReplacementDayRestoreDeletesOverrideAndRestoresWednesdayTimetable() throws {
        try withStore { store, context in
            let date = date(10)
            let key = SchoolDate(date, calendar: calendar)
            let hover = CalendarSchoolDayHover()
            XCTAssertEqual(store.baseSchoolCalendar.effectiveSchoolStatus(for: date, calendar: calendar), .replacementSchoolDay(.wednesday))
            store.resolve(key, as: .noSchool)
            XCTAssertEqual(store.effectiveSchoolStatus(for: date, calendar: calendar), .noSchool)
            let action = CalendarSchoolDayHover.action(for: date, in: store, calendar: calendar)
            XCTAssertEqual(action, .restoreSchoolCalendar)
            hover.headerEntered(date, action: action)
            XCTAssertEqual(hover.activeDate, date)
            hover.performAction(in: store, calendar: calendar)
            XCTAssertNil(store.personalOverride(for: key))
            XCTAssertTrue(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).isEmpty)
            XCTAssertEqual(store.effectiveSchoolStatus(for: date, calendar: calendar), .replacementSchoolDay(.wednesday))
            XCTAssertEqual(store.schoolCalendar.day(on: date, timetable: store.preferences.timetable, calendar: calendar)?.lessons,
                           store.baseSchoolCalendar.day(on: self.date(14), timetable: store.preferences.timetable, calendar: calendar)?.lessons)
        }
    }

    func testBaseHolidayHasNoHoverAction() throws {
        try withStore { store, context in
            let date = date(1)
            XCTAssertEqual(store.baseSchoolCalendar.effectiveSchoolStatus(for: date, calendar: calendar), .noSchool)
            XCTAssertNil(store.personalOverride(for: SchoolDate(date, calendar: calendar)))
            let action = CalendarSchoolDayHover.action(for: date, in: store, calendar: calendar)
            XCTAssertEqual(action, .none)
            let hover = CalendarSchoolDayHover()
            hover.headerEntered(date, action: action)
            XCTAssertNil(hover.activeDate)
            hover.performAction(in: store, calendar: calendar)
            XCTAssertTrue(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).isEmpty)
        }
    }

    func testMovingFromHeaderToActionCancelsDismissal() async throws {
        let hover = CalendarSchoolDayHover(dismissalDelay: .milliseconds(20))
        let date = date(12)
        hover.headerEntered(date, action: .markNoSchool)
        hover.headerExited(date)
        hover.actionEntered(date)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(hover.activeDate, date)
        hover.actionExited(date)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertNil(hover.activeDate)
    }

    func testHoverTransferWorksWhenEnterArrivesBeforeExit() async throws {
        let hover = CalendarSchoolDayHover(dismissalDelay: .milliseconds(20))
        let date = date(12)
        hover.headerEntered(date, action: .markNoSchool)
        hover.actionEntered(date)
        hover.headerExited(date)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(hover.activeDate, date)
        hover.headerEntered(date, action: .markNoSchool)
        hover.actionExited(date)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(hover.activeDate, date)
        hover.dismiss()
    }

    func testStaleExitFromPreviousDateDoesNotDismissNewHeader() async throws {
        let hover = CalendarSchoolDayHover(dismissalDelay: .milliseconds(20))
        let first = date(12)
        let second = date(13)
        hover.headerEntered(first, action: .markNoSchool)
        hover.actionEntered(first)
        hover.headerEntered(second, action: .markNoSchool)
        hover.actionExited(first)
        hover.headerExited(first)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(hover.activeDate, second)
        hover.dismiss()
    }

    func testActivatingShortcutPersistsOverrideHidesClassesAndKeepsBothEventSources() throws {
        try withStore { store, context in
            let date = date(12)
            let key = SchoolDate(date, calendar: calendar)
            let hover = CalendarSchoolDayHover()
            hover.headerEntered(date, action: CalendarSchoolDayHover.action(for: date, in: store, calendar: calendar))
            hover.performAction(in: store, calendar: calendar)
            XCTAssertNil(hover.activeDate)
            XCTAssertEqual(store.personalOverride(for: key), .noSchool)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).first?.status, .noSchool)
            let local = try CalendarSpecialEvent(title: "Personal", start: date.addingTimeInterval(3600))
            let external = CalendarGlanceEvent(id: UUID(), title: "External", start: date.addingTimeInterval(7200),
                                              end: date.addingTimeInterval(10800), isAllDay: false, calendarTitle: "External")
            let week = CalendarWeek(containing: date, calendar: calendar)
            let events = CalendarEventPresentation.merged(local: [local], external: [external], range: week.interval)
            let schedule = WeeklySchoolSchedule(week: week, school: store.schoolCalendar, timetable: store.preferences.timetable,
                                               events: events, calendar: calendar, lunchWindow: nil, placements: [:])
            XCTAssertEqual(schedule.days[1].school?.lessons, [])
            XCTAssertEqual(schedule.days[1].events.map(\.title), ["Personal", "External"])
            store.removePersonalOverride(for: key)
            XCTAssertEqual(store.effectiveSchoolStatus(for: date, calendar: calendar), .regularSchoolDay)
        }
    }

    func testActivationRechecksStatusAndDoesNotResolvePendingSilently() throws {
        try withStore { store, context in
            let date = date(12)
            let key = SchoolDate(date, calendar: calendar)
            let hover = CalendarSchoolDayHover()
            hover.headerEntered(date, action: .markNoSchool)
            store.markPending(key)
            hover.performAction(in: store, calendar: calendar)
            XCTAssertEqual(store.effectiveSchoolStatus(for: date, calendar: calendar), .pending)
            XCTAssertNil(store.personalOverride(for: key))
            XCTAssertTrue(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).isEmpty)
            XCTAssertEqual(store.schoolCalendar.pendingDates(from: key, through: key), [key])
        }
    }

    private func withStore(_ action: (SchoolScheduleStore, ModelContext) throws -> Void) throws {
        let name = "EasyTODOTests.SchoolHover.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let store = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
        try action(store, container.mainContext)
    }

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }
}
