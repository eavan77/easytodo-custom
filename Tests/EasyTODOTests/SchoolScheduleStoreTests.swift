import XCTest
@testable import EasyTODO

@MainActor
final class SchoolScheduleStoreTests: XCTestCase {
    func testResolutionsAndDynamicCategoryMappingsPersistIndependently() throws {
        let name = "EasyTODOTests.SchoolSchedule.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let container = try PersistenceController.modelContainer(inMemory: true)
        let store = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
        let date = SchoolDate(2026, 10, 12)
        let category = TaskCategory(name: "New category", colorIdentifier: CategoryColor.teal.rawValue)
        store.markPending(date)
        store.mapEvent("occurrence-key", to: category.id)
        store.placeEvent("occurrence-key", in: .lunch)
        store.setLunchWindow(SchoolLunchWindow(startMinute: 720, endMinute: 780))
        var restored = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
        XCTAssertEqual(restored.schoolCalendar.overrides[date], .pending)
        XCTAssertEqual(restored.preferences.eventCategories["occurrence-key"], category.id)
        XCTAssertEqual(restored.preferences.eventPlacements["occurrence-key"], .lunch)
        XCTAssertEqual(restored.preferences.lunchWindow?.endMinute, 780)
        XCTAssertEqual(restored.schoolCalendar.overrides[SchoolDate(2026, 10, 10)], .replacementSchoolDay(.wednesday))
        restored.resolve(date, as: .useTimetable(.thursday))
        restored.mapEvent("occurrence-key", to: nil)
        restored = SchoolScheduleStore(defaults: defaults, modelContext: container.mainContext)
        XCTAssertEqual(restored.personalOverride(for: date), .replacementSchoolDay(.thursday))
        XCTAssertEqual(restored.baseSchoolCalendar.overrides[date], .pending)
        XCTAssertNil(restored.preferences.eventCategories["occurrence-key"])
        XCTAssertNil(restored.persistenceError)
    }

    func testTimetableCanBeEditedAndRestoredWithoutChangingSeed() throws {
        let name = "EasyTODOTests.SchoolTimetable.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SchoolScheduleStore(defaults: defaults)
        var edited = SchoolTimetable.semester1
        edited.days[.friday] = [SchoolLesson(period: 6, course: "Custom")]
        store.setTimetable(edited)
        let restored = SchoolScheduleStore(defaults: defaults)
        XCTAssertEqual(restored.preferences.timetable.lessons(on: .friday).first?.course, "Custom")
        XCTAssertTrue(SchoolTimetable.semester1.lessons(on: .friday).isEmpty)
    }
}
