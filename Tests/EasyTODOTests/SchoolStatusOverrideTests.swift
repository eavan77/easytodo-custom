import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class SchoolStatusOverrideTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return result
    }

    func testNormalBaseDayWithoutPersonalOverrideResolvesNormally() throws {
        try withStore { store, _, _ in
            let date = SchoolDate(2026, 10, 12)
            XCTAssertNil(store.personalOverride(for: date))
            XCTAssertEqual(status(store, date), .regularSchoolDay)
            XCTAssertEqual(lessons(store, date)?.map(\.course), ["Lit", "Research", "CM"])
        }
    }

    func testNoSchoolOverrideSuppressesClassesAndRemovalRestoresBase() throws {
        try withStore { store, context, _ in
            let date = SchoolDate(2026, 10, 12)
            store.resolve(date, as: .noSchool)
            XCTAssertEqual(status(store, date), .noSchool)
            XCTAssertEqual(lessons(store, date), [])
            XCTAssertEqual(store.baseSchoolCalendar.effectiveSchoolStatus(for: date.date(in: calendar)!, calendar: calendar), .regularSchoolDay)
            store.removePersonalOverride(for: date)
            XCTAssertNil(store.personalOverride(for: date))
            XCTAssertEqual(status(store, date), .regularSchoolDay)
            XCTAssertEqual(lessons(store, date)?.map(\.course), ["Lit", "Research", "CM"])
            XCTAssertTrue(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).isEmpty)
        }
    }

    func testPersonalSaturdayReplacementUsesExistingWednesdayTimetable() throws {
        try withStore { store, _, _ in
            let date = SchoolDate(2026, 10, 17)
            store.resolve(date, as: .useTimetable(.wednesday))
            XCTAssertEqual(status(store, date), .replacementSchoolDay(.wednesday))
            XCTAssertEqual(lessons(store, date), SchoolTimetable.semester1.lessons(on: .wednesday))
            XCTAssertEqual(lessons(store, date)?.filter { $0.session == .afterLunch }.map(\.course), ["Research"])
        }
    }

    func testBaseHolidayCanBeOverriddenAndRestored() throws {
        try withStore { store, _, _ in
            let date = SchoolDate(2026, 9, 29)
            XCTAssertEqual(status(store, date), .noSchool)
            store.resolve(date, as: .normalSchool)
            XCTAssertEqual(status(store, date), .regularSchoolDay)
            XCTAssertEqual(lessons(store, date)?.map(\.course), ["Adv.Math", "Lit", "PE", "Man"])
            XCTAssertEqual(store.baseSchoolCalendar.overrides[date], .noSchool)
            store.removePersonalOverride(for: date)
            XCTAssertEqual(status(store, date), .noSchool)
            XCTAssertEqual(lessons(store, date), [])
        }
    }

    func testRemovingPersonalOverrideRestoresSeededReplacement() throws {
        try withStore { store, _, _ in
            let date = SchoolDate(2026, 10, 10)
            store.resolve(date, as: .noSchool)
            store.removePersonalOverride(for: date)
            XCTAssertEqual(status(store, date), .replacementSchoolDay(.wednesday))
            XCTAssertEqual(lessons(store, date), SchoolTimetable.semester1.lessons(on: .wednesday))
        }
    }

    func testPendingResolutionUsesOnePersonalRecordAndRemovingRestoresPending() throws {
        try withStore { store, context, _ in
            let date = SchoolDate(2026, 10, 12)
            store.markPending(date)
            XCTAssertEqual(status(store, date), .pending)
            XCTAssertNil(lessons(store, date))
            XCTAssertEqual(store.schoolCalendar.pendingDates(from: date, through: date), [date])
            store.resolve(date, as: .normalSchool)
            store.resolve(date, as: .noSchool)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).count, 1)
            XCTAssertEqual(status(store, date), .noSchool)
            XCTAssertTrue(store.schoolCalendar.pendingDates(from: date, through: date).isEmpty)
            XCTAssertEqual(store.baseSchoolCalendar.overrides[date], .pending)
            store.removePersonalOverride(for: date)
            XCTAssertEqual(status(store, date), .pending)
            XCTAssertEqual(store.schoolCalendar.pendingDates(from: date, through: date), [date])
        }
    }

    func testPersonalNoSchoolStillDisplaysLocalAndExternalEvents() throws {
        try withStore { store, _, _ in
            let date = SchoolDate(2026, 10, 12)
            let start = date.date(in: calendar)!
            store.resolve(date, as: .noSchool)
            let local = try CalendarSpecialEvent(title: "Personal", start: start.addingTimeInterval(3600))
            let external = CalendarGlanceEvent(id: UUID(), title: "External", start: start.addingTimeInterval(7200),
                                              end: start.addingTimeInterval(10800), isAllDay: false, calendarTitle: "External")
            let week = CalendarWeek(containing: start, calendar: calendar)
            let events = CalendarEventPresentation.merged(local: [local], external: [external], range: week.interval)
            let schedule = WeeklySchoolSchedule(week: week, school: store.schoolCalendar, timetable: store.preferences.timetable,
                                               events: events, calendar: calendar, lunchWindow: nil, placements: [:])
            XCTAssertEqual(schedule.days[1].school?.lessons, [])
            XCTAssertEqual(schedule.days[1].events.map(\.title), ["Personal", "External"])
        }
    }

    func testOverrideAndRemovalPersistThroughSwiftDataReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("School.store")
        let name = "EasyTODOTests.SchoolOverrides.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let date = SchoolDate(2026, 10, 12)
        do {
            let container = try PersistenceController.modelContainer(storeURL: url)
            let store = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
            store.resolve(date, as: .useTimetable(.tuesday))
            XCTAssertNil(store.persistenceError)
        }
        do {
            let container = try PersistenceController.modelContainer(storeURL: url)
            let store = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
            XCTAssertEqual(status(store, date), .replacementSchoolDay(.tuesday))
            store.removePersonalOverride(for: date)
            XCTAssertNil(store.persistenceError)
        }
        let reopened = try PersistenceController.modelContainer(storeURL: url)
        let store = SchoolScheduleStore(defaults: defaults, modelContext: reopened.mainContext)
        XCTAssertNil(store.personalOverride(for: date))
        XCTAssertEqual(status(store, date), .regularSchoolDay)
    }

    func testLegacyMigrationMovesResolvedChoicesAndPreservesPendingBase() throws {
        try withStore { _, context, defaults in
            var legacy = SchoolSchedulePreferences()
            let resolved = SchoolDate(2026, 10, 12)
            let pending = SchoolDate(2026, 10, 13)
            legacy.schoolOverrides = [resolved: .noSchool, pending: .pending]
            legacy.baseSchoolOverrides = nil
            defaults.set(try JSONEncoder().encode(legacy), forKey: "EasyTODO.schoolSchedule.semester1.v1")
            let migrated = SchoolScheduleStore(defaults: defaults, modelContext: context)
            XCTAssertNil(migrated.persistenceError)
            XCTAssertEqual(migrated.personalOverride(for: resolved), .noSchool)
            XCTAssertNil(migrated.personalOverride(for: pending))
            XCTAssertEqual(status(migrated, pending), .pending)
            XCTAssertTrue(migrated.preferences.schoolOverrides.isEmpty)
            migrated.connectSchoolOverrides(in: context)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).count, 1)
            migrated.removePersonalOverride(for: resolved)
            XCTAssertEqual(status(migrated, resolved), .regularSchoolDay)
        }
    }

    func testEffectiveAPIIsReusableWithoutAnyCalendarView() {
        var school = SchoolCalendar.semester1
        let date = SchoolDate(2026, 10, 12)
        school.personalOverrides = [date: .noSchool]
        XCTAssertEqual(school.effectiveSchoolStatus(for: date.date(in: calendar)!, calendar: calendar), .noSchool)
        XCTAssertEqual(SchoolCalendar.semester1.effectiveSchoolStatus(for: date.date(in: calendar)!, calendar: calendar), .regularSchoolDay)
    }

    func testSchemaMigrationPreservesExistingManualEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Existing.store")
        let id: UUID = try {
            let oldSchema = Schema([TodoTask.self, TaskCategory.self, CalendarSpecialEvent.self, WorkBlock.self,
                                    TaskBlockDefinition.self, DayCapacityTemplate.self, DayCapacityOverride.self,
                                    ScheduleConflictAcknowledgement.self])
            let container = try ModelContainer(for: oldSchema, configurations: [ModelConfiguration("EasyTODO", schema: oldSchema, url: url)])
            let event = try CalendarSpecialEvent(title: "Keep event", start: .now)
            container.mainContext.insert(event)
            try container.mainContext.save()
            return event.id
        }()
        let migrated = try PersistenceController.modelContainer(storeURL: url)
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<CalendarSpecialEvent>()).first?.id, id)
        migrated.mainContext.insert(SchoolStatusOverride(date: SchoolDate(2026, 10, 12), resolution: .noSchool))
        try migrated.mainContext.save()
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<SchoolStatusOverride>()).count, 1)
    }

    private func withStore(_ action: (SchoolScheduleStore, ModelContext, UserDefaults) throws -> Void) throws {
        let name = "EasyTODOTests.SchoolOverrides.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let store = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
        try action(store, container.mainContext, defaults)
    }

    private func status(_ store: SchoolScheduleStore, _ date: SchoolDate) -> SchoolDayStatus? {
        store.effectiveSchoolStatus(for: date.date(in: calendar)!, calendar: calendar)
    }

    private func lessons(_ store: SchoolScheduleStore, _ date: SchoolDate) -> [SchoolLesson]? {
        store.schoolCalendar.day(on: date.date(in: calendar)!, timetable: store.preferences.timetable, calendar: calendar)?.lessons
    }
}
