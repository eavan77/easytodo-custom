import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class CalendarInteractionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testPreviousNextWeekCrossYearAndPreserveSundayStart() {
        var navigation = CalendarWeekNavigation(now: date(2027, 1, 1))
        navigation.move(by: 1, calendar: calendar)
        XCTAssertEqual(navigation.week(calendar: calendar).days[0], date(2027, 1, 3))
        navigation.move(by: -2, calendar: calendar)
        XCTAssertEqual(navigation.week(calendar: calendar).days[0], date(2026, 12, 20))
    }

    func testTodayReturnsToCurrentWeekAndRefreshPreservesBrowsing() {
        var navigation = CalendarWeekNavigation(now: date(2026, 10, 1))
        navigation.move(by: 2, calendar: calendar)
        let browsing = navigation.week(calendar: calendar)
        navigation.refresh(now: date(2026, 11, 1))
        XCTAssertEqual(navigation.week(calendar: calendar), browsing)
        navigation.showToday(now: date(2026, 11, 1))
        XCTAssertEqual(navigation.week(calendar: calendar).days[0], date(2026, 11, 1))
        navigation.refresh(now: date(2026, 11, 8))
        XCTAssertEqual(navigation.week(calendar: calendar).days[0], date(2026, 11, 8))
    }

    func testNavigateToNewEventShowsItsWeek() {
        var navigation = CalendarWeekNavigation(now: date(2026, 10, 1))
        navigation.show(date(2027, 1, 7), now: date(2026, 10, 1), calendar: calendar)
        XCTAssertEqual(navigation.week(calendar: calendar).days[0], date(2027, 1, 3))
        XCTAssertFalse(navigation.followsToday)
    }

    func testSwipeDirectionThresholdAndVerticalScrolling() {
        var swipe = CalendarWeekSwipeState()
        swipe.update(x: 30, y: 1)
        XCTAssertNil(swipe.completedStep())
        swipe.update(x: 30, y: 1)
        XCTAssertEqual(swipe.completedStep(), 1)
        swipe.reset()
        swipe.update(x: -60, y: 1)
        XCTAssertEqual(swipe.completedStep(), -1)
        swipe.reset()
        swipe.update(x: 1, y: 20)
        swipe.update(x: 70, y: 1)
        XCTAssertNil(swipe.completedStep(), "A vertical gesture must never turn into week navigation")
        swipe.reset()
        XCTAssertNil(swipe.completedStep())
    }

    func testLocalEventAndCategorySurviveStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Events.store")
        let ids: (UUID, UUID) = try {
            let container = try PersistenceController.modelContainer(storeURL: url)
            let category = TaskCategory(name: "Future category", colorIdentifier: CategoryColor.teal.rawValue)
            let event = try CalendarSpecialEvent(title: "  Meeting  ", start: date(2026, 10, 12, 10),
                                                 end: date(2026, 10, 12, 11), categoryID: category.id)
            container.mainContext.insert(category)
            container.mainContext.insert(event)
            try container.mainContext.save()
            return (event.id, category.id)
        }()
        let reopened = try PersistenceController.modelContainer(storeURL: url)
        let event = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<CalendarSpecialEvent>()).first)
        XCTAssertEqual(event.id, ids.0)
        XCTAssertEqual(event.categoryID, ids.1)
        XCTAssertEqual(event.title, "Meeting")
        XCTAssertEqual(event.start, date(2026, 10, 12, 10))
        XCTAssertEqual(event.end, date(2026, 10, 12, 11))
        let categories = try reopened.mainContext.fetch(FetchDescriptor<TaskCategory>())
        XCTAssertEqual(CalendarEventPresentation.category(for: CalendarEventPresentation.snapshot(event),
                                                          mappings: [:], categories: categories)?.color, .teal)
    }

    func testUncategorizedAndDeletedCategoriesResolveToNeutral() throws {
        let category = TaskCategory(name: "Any new category", colorIdentifier: CategoryColor.pink.rawValue)
        let event = try CalendarSpecialEvent(title: "Personal", start: date(2026, 10, 12, 10))
        XCTAssertNil(CalendarEventPresentation.category(for: CalendarEventPresentation.snapshot(event), mappings: [:], categories: [category]))
        event.categoryID = category.id
        XCTAssertEqual(CalendarEventPresentation.category(for: CalendarEventPresentation.snapshot(event), mappings: [:], categories: [category])?.color, .pink)
        category.color = .green
        XCTAssertEqual(CalendarEventPresentation.category(for: CalendarEventPresentation.snapshot(event), mappings: [:], categories: [category])?.color, .green)
        XCTAssertNil(CalendarEventPresentation.category(for: CalendarEventPresentation.snapshot(event), mappings: [:], categories: []))
    }

    func testMergingLocalAndEventKitKeepsBothSourcesAndFiltersWeek() throws {
        let local = try CalendarSpecialEvent(title: "Same title", start: date(2026, 10, 12, 10))
        let outside = try CalendarSpecialEvent(title: "Outside", start: date(2026, 11, 1))
        let external = CalendarGlanceEvent(id: UUID(), title: "Same title", start: date(2026, 10, 12, 9),
                                          end: date(2026, 10, 12, 10), isAllDay: false, calendarTitle: "External",
                                          calendarIdentifier: "calendar", eventIdentifier: "event")
        let range = CalendarWeek(containing: date(2026, 10, 12), calendar: calendar).interval
        let merged = CalendarEventPresentation.merged(local: [local, outside], external: [external], range: range)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.map(\.source), [.eventKit, .easyTODO(local.id)])
        XCTAssertNotEqual(merged[0].mappingKey, merged[1].mappingKey)
        let category = TaskCategory(name: "External color")
        XCTAssertEqual(CalendarEventPresentation.category(for: external, mappings: [external.mappingKey!: category.id], categories: [category])?.id, category.id)
    }

    func testManualLunchEventExpandsSharedBandWithoutChangingSchoolDay() throws {
        let event = try CalendarSpecialEvent(title: "Lunch meeting", start: date(2026, 10, 12, 12),
                                            end: date(2026, 10, 12, 13))
        let week = CalendarWeek(containing: event.start, calendar: calendar)
        let events = CalendarEventPresentation.merged(local: [event], external: [], range: week.interval)
        let schedule = WeeklySchoolSchedule(week: week, school: .semester1, timetable: .semester1,
                                           events: events, calendar: calendar,
                                           lunchWindow: SchoolLunchWindow(startMinute: 720, endMinute: 780), placements: [:])
        XCTAssertTrue(schedule.expandsLunch)
        XCTAssertEqual(schedule.events(on: schedule.days[1], in: .lunch).count, 1)
        XCTAssertTrue(schedule.events(on: schedule.days[2], in: .lunch).isEmpty)
        XCTAssertEqual(schedule.days[1].school?.lessons?.map(\.course), ["Lit", "Research", "CM"])
        let placed = WeeklySchoolSchedule(week: week, school: .semester1, timetable: .semester1,
                                         events: events, calendar: calendar, lunchWindow: nil,
                                         placements: [events[0].mappingKey!: .lunch])
        XCTAssertTrue(placed.expandsLunch)
    }

    func testManualAllDayIsOneCalendarDayAcrossDSTAndDoesNotExpandLunch() throws {
        let event = try CalendarSpecialEvent(title: "All day", start: date(2026, 3, 8, 14), isAllDay: true, calendar: calendar)
        XCTAssertEqual(event.start, date(2026, 3, 8))
        XCTAssertEqual(event.end, date(2026, 3, 9))
        XCTAssertEqual(event.end!.timeIntervalSince(event.start), 23 * 3600)
        let week = CalendarWeek(containing: event.start, calendar: calendar)
        let schedule = WeeklySchoolSchedule(week: week, school: .semester1, timetable: .semester1,
                                           events: [CalendarEventPresentation.snapshot(event)], calendar: calendar,
                                           lunchWindow: SchoolLunchWindow(startMinute: 720, endMinute: 780), placements: [:])
        XCTAssertFalse(schedule.expandsLunch)
        XCTAssertEqual(schedule.days[0].events.count, 1)
        XCTAssertTrue(schedule.days[1].events.isEmpty)
    }

    func testInvalidManualEventIsRejectedAndOptionalEndIsSupported() throws {
        XCTAssertThrowsError(try CalendarSpecialEvent(title: " \n ", start: .now))
        XCTAssertThrowsError(try CalendarSpecialEvent(title: "Invalid", start: date(2026, 10, 12, 12), end: date(2026, 10, 12, 11)))
        let event = try CalendarSpecialEvent(title: "No end time", start: date(2026, 10, 12, 12))
        XCTAssertNil(event.end)
        XCTAssertEqual(CalendarEventPresentation.snapshot(event).end, event.start)
    }

    func testExistingStoreMigratesWithoutChangingTasksOrCategories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Existing.store")
        let taskID: UUID = try {
            let oldSchema = Schema([TodoTask.self, TaskCategory.self, WorkBlock.self, TaskBlockDefinition.self,
                                    DayCapacityTemplate.self, DayCapacityOverride.self, ScheduleConflictAcknowledgement.self])
            let configuration = ModelConfiguration("EasyTODO", schema: oldSchema, url: url)
            let container = try ModelContainer(for: oldSchema, configurations: [configuration])
            let category = TaskCategory(name: "Existing category")
            let task = TodoTask(title: "Keep existing task", category: category)
            container.mainContext.insert(category)
            container.mainContext.insert(task)
            try container.mainContext.save()
            return task.id
        }()
        let migrated = try PersistenceController.modelContainer(storeURL: url)
        let task = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        XCTAssertEqual(task.id, taskID)
        XCTAssertEqual(task.category?.name, "Existing category")
        let event = try CalendarSpecialEvent(title: "New event", start: date(2026, 10, 12))
        migrated.mainContext.insert(event)
        try migrated.mainContext.save()
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<CalendarSpecialEvent>()).count, 1)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
