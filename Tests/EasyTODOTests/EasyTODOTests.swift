import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class EasyTODOTests: XCTestCase {
    func testMenuBarConfigurationDoesNotCreateAppKitUIBeforeLaunchFinishes() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)

        MenuBarManager.shared.configure(modelContainer: container)

        XCTAssertFalse(MenuBarManager.shared.isStatusItemInstalledForTesting)
    }

    func testTaskDefaultsToIncomplete() {
        let task = TodoTask(title: "Read paper", sortOrder: 2)

        XCTAssertEqual(task.title, "Read paper")
        XCTAssertFalse(task.isCompleted)
        XCTAssertEqual(task.sortOrder, 2)
        XCTAssertEqual(task.priority, .notUrgentImportant)
        XCTAssertNil(task.scheduledDate)
    }

    func testTaskScheduledDateIsStoredAsStartOfDay() throws {
        let calendar = Calendar.current
        let futureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 18, hour: 15)))
        let task = TodoTask(title: "Plan launch", scheduledDate: futureDate)
        let expectedDay = calendar.startOfDay(for: futureDate)

        XCTAssertEqual(task.scheduledDate, Optional(expectedDay))
        XCTAssertTrue(task.isScheduled(on: futureDate, calendar: calendar))
        XCTAssertTrue(task.isScheduled(on: expectedDay, calendar: calendar))
    }

    func testTaskCanStorePriority() {
        let task = TodoTask(title: "Finish report", priority: .importantUrgent)

        XCTAssertEqual(task.priority, .importantUrgent)

        task.priority = .notUrgentImportant

        XCTAssertEqual(task.priority, .notUrgentImportant)
    }

    func testTaskCanStoreRepeatRule() {
        let task = TodoTask(title: "Standup", repeatRule: .daily)

        XCTAssertEqual(task.repeatRule, .daily)

        task.repeatRule = .weekly

        XCTAssertEqual(task.repeatRule, .weekly)
    }

    func testLegacyPriorityValuesAreMapped() {
        XCTAssertEqual(TaskPriority.normalized(from: "urgent"), .importantUrgent)
        XCTAssertEqual(TaskPriority.normalized(from: "high"), .notUrgentImportant)
        XCTAssertEqual(TaskPriority.normalized(from: "normal"), .notUrgentNotImportant)
        XCTAssertEqual(TaskPriority.normalized(from: nil), .notUrgentImportant)
    }

    func testInMemoryContainerPersistsInsertedTask() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let task = TodoTask(title: "Reply email", sortOrder: 0)

        context.insert(task)
        try context.save()

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Reply email")
    }

    func testCanAddMultipleTasksInARow() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9)))
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext

        let first = try TaskCreation.addTask(title: "First task", scheduledDate: today, in: context, calendar: calendar)
        let second = try TaskCreation.addTask(title: "Second task", scheduledDate: today, in: context, calendar: calendar)
        let third = try TaskCreation.addTask(title: "Third task", scheduledDate: today, in: context, calendar: calendar)

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let todayTasks = TaskListOrdering.ordered(tasks.filter { $0.isScheduled(on: today, calendar: calendar) })

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
        XCTAssertEqual(todayTasks.map(\.title), ["First task", "Second task", "Third task"])
        XCTAssertEqual(todayTasks.map(\.sortOrder), [0, 1, 2])
    }

    func testBlankTaskTitleDoesNotInterruptLaterAdds() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9)))
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext

        let blank = try TaskCreation.addTask(title: "   ", scheduledDate: today, in: context, calendar: calendar)
        let task = try TaskCreation.addTask(title: "Valid task", scheduledDate: today, in: context, calendar: calendar)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())

        XCTAssertNil(blank)
        XCTAssertNotNil(task)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Valid task")
        XCTAssertEqual(tasks.first?.sortOrder, 0)
    }

    func testLegacyPriorityDoesNotControlUrgencyOrdering() {
        let firstGreen = TodoTask(title: "First green", sortOrder: 0, priority: .notUrgentImportant)
        let red = TodoTask(title: "Red", sortOrder: 1, priority: .importantUrgent)
        let yellow = TodoTask(title: "Yellow", sortOrder: 2, priority: .urgentNotImportant)
        let secondGreen = TodoTask(title: "Second green", sortOrder: 3, priority: .notUrgentImportant)

        XCTAssertEqual(
            TaskUrgencyOrdering.ordered([firstGreen, red, yellow, secondGreen]).map(\.title),
            ["First green", "Red", "Yellow", "Second green"]
        )
    }

    func testDeadlineOrderingOverdueThenUpcomingThenNoDeadline() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12)))
        let overdue = TodoTask(title: "Overdue", createdAt: now, scheduledDate: now.addingTimeInterval(-3600), hasExplicitDueTime: true)
        let upcoming = TodoTask(title: "Upcoming", createdAt: now, scheduledDate: now.addingTimeInterval(3600), hasExplicitDueTime: true)
        let later = TodoTask(title: "Later", createdAt: now, scheduledDate: now.addingTimeInterval(7200), hasExplicitDueTime: true)
        let none = TodoTask(title: "No deadline", createdAt: now)

        XCTAssertEqual(TaskUrgencyOrdering.ordered([none, later, upcoming, overdue], now: now, calendar: calendar).map(\.title),
                       ["Overdue", "Upcoming", "Later", "No deadline"])
    }

    func testPrimaryGlobalListIncludesUnfinishedTasksAcrossCalendarDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 12)))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: today))
        let tasks = [
            TodoTask(title: "Today", scheduledDate: today),
            TodoTask(title: "Tomorrow", scheduledDate: tomorrow),
            TodoTask(title: "Next week", scheduledDate: nextWeek),
            TodoTask(title: "Whenever")
        ]

        XCTAssertEqual(TaskUrgencyOrdering.visibleTasks(from: tasks, now: today, calendar: calendar).map(\.title),
                       ["Today", "Tomorrow", "Next week", "Whenever"])
    }

    func testHiddenWidgetShowRestoresCollapsedLauncher() {
        var state = WidgetHoverState()
        state.hide()
        state.show()
        XCTAssertEqual(state.visibility, .launcher)
    }

    func testLauncherPointerEntryExpandsAndExpandedEntryStaysExpanded() {
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        XCTAssertEqual(state.visibility, .expanded)
        state.pointerEntered()
        XCTAssertEqual(state.visibility, .expanded)
    }

    func testPointerExitSchedulesCollapseAndReentryCancelsIt() {
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        state.pointerExited()
        XCTAssertTrue(state.isCollapsePending)
        state.pointerEntered()
        XCTAssertFalse(state.isCollapsePending)
        state.collapseGracePeriodCompleted()
        XCTAssertEqual(state.visibility, .expanded)
    }

    func testGraceCompletionCollapsesExpandedWidget() {
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        state.pointerExited()
        state.collapseGracePeriodCompleted()
        XCTAssertEqual(state.visibility, .launcher)
    }

    func testInteractionLockPreventsCollapseUntilReleasedOutside() {
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        state.beginInteraction()
        state.pointerExited()
        state.collapseGracePeriodCompleted()
        XCTAssertEqual(state.visibility, .expanded)
        XCTAssertFalse(state.isCollapsePending)

        state.endInteraction()
        XCTAssertTrue(state.isCollapsePending)
        state.collapseGracePeriodCompleted()
        XCTAssertEqual(state.visibility, .launcher)
    }

    func testHideAndShowWidgetNeverLeavesExpandedStateStuck() {
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        state.hide()
        XCTAssertEqual(state.visibility, .hidden)
        state.show()
        XCTAssertEqual(state.visibility, .launcher)
        XCTAssertFalse(state.isCollapsePending)
        XCTAssertEqual(state.interactionLockCount, 0)
    }

    func testRepeatedShowRequestsCreateOnlyOnePanel() {
        var ownership = WidgetPanelOwnershipState()
        XCTAssertTrue(ownership.requestCreation())
        XCTAssertFalse(ownership.requestCreation())
        XCTAssertFalse(ownership.requestCreation())
    }

    func testQuadrantDetectionMapsEveryScreenQuadrantToCorner() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
        XCTAssertEqual(WidgetCorner.quadrant(containing: CGPoint(x: 200, y: 700), in: visible), .topLeft)
        XCTAssertEqual(WidgetCorner.quadrant(containing: CGPoint(x: 1000, y: 700), in: visible), .topRight)
        XCTAssertEqual(WidgetCorner.quadrant(containing: CGPoint(x: 200, y: 100), in: visible), .bottomLeft)
        XCTAssertEqual(WidgetCorner.quadrant(containing: CGPoint(x: 1000, y: 100), in: visible), .bottomRight)
    }

    func testPanelDragUsesGlobalMouseDeltaWithoutChangingPanelSize() {
        let startingFrame = CGRect(x: 16, y: 16, width: 276, height: 350)
        let draggedFrame = WidgetPanelGeometry.draggedFrame(
            startingFrame: startingFrame,
            startingMouseLocation: CGPoint(x: 100, y: 100),
            currentMouseLocation: CGPoint(x: 850, y: 650)
        )

        XCTAssertEqual(draggedFrame.origin, CGPoint(x: 766, y: 566))
        XCTAssertEqual(draggedFrame.size, startingFrame.size)
        XCTAssertEqual(
            WidgetCorner.quadrant(containing: CGPoint(x: draggedFrame.midX, y: draggedFrame.midY), in: CGRect(x: 0, y: 0, width: 1440, height: 875)),
            .topRight
        )
    }

    func testEveryCornerProducesCorrectExpandedGeometryInsideVisibleFrame() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 700)
        let size = CGSize(width: 276, height: 350)
        let inset: CGFloat = 16

        let topLeft = WidgetPanelGeometry.frame(size: size, corner: .topLeft, visibleFrame: visible, inset: inset)
        let topRight = WidgetPanelGeometry.frame(size: size, corner: .topRight, visibleFrame: visible, inset: inset)
        let bottomLeft = WidgetPanelGeometry.frame(size: size, corner: .bottomLeft, visibleFrame: visible, inset: inset)
        let bottomRight = WidgetPanelGeometry.frame(size: size, corner: .bottomRight, visibleFrame: visible, inset: inset)

        XCTAssertEqual(topLeft.minX, visible.minX + inset)
        XCTAssertEqual(topLeft.maxY, visible.maxY - inset)
        XCTAssertEqual(topRight.maxX, visible.maxX - inset)
        XCTAssertEqual(topRight.maxY, visible.maxY - inset)
        XCTAssertEqual(bottomLeft.minX, visible.minX + inset)
        XCTAssertEqual(bottomLeft.minY, visible.minY + inset)
        XCTAssertEqual(bottomRight.maxX, visible.maxX - inset)
        XCTAssertEqual(bottomRight.minY, visible.minY + inset)
        for corner in WidgetCorner.allCases {
            XCTAssertTrue(visible.contains(WidgetPanelGeometry.frame(size: size, corner: corner, visibleFrame: visible, inset: inset)))
        }
    }

    func testCollapseAndExpansionPreserveSelectedCornerWithoutDrift() {
        let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for corner in WidgetCorner.allCases {
            let launcher = WidgetPanelGeometry.frame(size: CGSize(width: 40, height: 40), corner: corner, visibleFrame: visible, inset: 16)
            let expanded = WidgetPanelGeometry.frame(size: CGSize(width: 276, height: 350), corner: corner, visibleFrame: visible, inset: 16)
            let launcherAgain = WidgetPanelGeometry.frame(size: CGSize(width: 40, height: 40), corner: corner, visibleFrame: visible, inset: 16)
            XCTAssertEqual(launcherAgain, launcher)
            XCTAssertTrue(visible.contains(expanded))
        }
    }

    func testWidgetCornerStoreRoundTripsPersistedCorner() throws {
        let suiteName = "EasyTODOTests.WidgetCornerStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetCornerStore(defaults: defaults)

        XCTAssertNil(store.load())
        store.save(.bottomLeft)
        XCTAssertEqual(store.load(), .bottomLeft)
    }

    func testRestoredCornerControlsLauncherFrameAfterShowOrRelaunch() throws {
        let suiteName = "EasyTODOTests.RestoredWidgetCorner.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetCornerStore(defaults: defaults)
        let visible = CGRect(x: 80, y: 30, width: 1200, height: 800)
        store.save(.bottomRight)

        let restored = try XCTUnwrap(store.load())
        let launcher = WidgetPanelGeometry.frame(size: CGSize(width: 40, height: 40), corner: restored, visibleFrame: visible, inset: 16)

        XCTAssertEqual(launcher.maxX, visible.maxX - 16)
        XCTAssertEqual(launcher.minY, visible.minY + 16)
    }

    func testDragInteractionLockPreventsHoverCollapse() {
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        state.beginInteraction()
        state.pointerExited()
        state.collapseGracePeriodCompleted()

        XCTAssertEqual(state.visibility, .expanded)
        XCTAssertEqual(state.interactionLockCount, 1)
    }

    func testDateOnlyDeadlineUsesEndOfLocalDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 8)))
        let task = TodoTask(title: "Date only", scheduledDate: day)
        let deadline = try XCTUnwrap(task.effectiveDeadline(in: calendar))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 18)))

        XCTAssertEqual(calendar.component(.hour, from: deadline), 23)
        XCTAssertEqual(calendar.component(.minute, from: deadline), 59)
        XCTAssertFalse(deadline < evening)
    }

    func testExplicitDueTimeIsPreserved() throws {
        let calendar = Calendar(identifier: .gregorian)
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 18, minute: 30)))
        let task = TodoTask(title: "Submit", scheduledDate: due, hasExplicitDueTime: true)

        XCTAssertTrue(task.hasExplicitDueTime)
        XCTAssertEqual(task.scheduledDate, due)
        XCTAssertEqual(task.effectiveDeadline(in: calendar), due)
    }

    func testEquivalentDeadlinesUseCreationTime() throws {
        let calendar = Calendar(identifier: .gregorian)
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 3)))
        let early = TodoTask(title: "Early", createdAt: due.addingTimeInterval(-20), scheduledDate: due)
        let late = TodoTask(title: "Late", createdAt: due.addingTimeInterval(-10), scheduledDate: due)
        XCTAssertEqual(TaskUrgencyOrdering.ordered([late, early], now: due.addingTimeInterval(-100), calendar: calendar).map(\.title), ["Early", "Late"])
    }

    func testWidgetVisibilityExcludesCompletedAndFiltersCategory() {
        let school = TaskCategory(name: "School")
        let schoolTask = TodoTask(title: "Essay", category: school)
        let personalTask = TodoTask(title: "Laundry")
        let completed = TodoTask(title: "Done", isCompleted: true, category: school)

        XCTAssertEqual(TaskUrgencyOrdering.visibleTasks(from: [completed, personalTask, schoolTask]).count, 2)
        XCTAssertEqual(TaskUrgencyOrdering.visibleTasks(from: [completed, personalTask, schoolTask], filter: .category(school.id)).map(\.title), ["Essay"])
        XCTAssertEqual(TaskUrgencyOrdering.visibleTasks(from: [completed, personalTask, schoolTask], filter: .uncategorized).map(\.title), ["Laundry"])
    }

    func testDeletingCategoryLeavesTaskUncategorized() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let category = TaskCategory(name: "Personal")
        let task = TodoTask(title: "Call dentist", category: category)
        context.insert(category)
        context.insert(task)
        try context.save()

        context.delete(category)
        try context.save()

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertNil(tasks[0].category)
    }

    func testCategoryCRUDAndColorChangesPersist() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let category = TaskCategory(name: "TEST", colorIdentifier: CategoryColor.purple.rawValue)
        context.insert(category)
        try context.save()

        var fetched = try context.fetch(FetchDescriptor<TaskCategory>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].name, "TEST")
        XCTAssertEqual(fetched[0].color, .purple)

        fetched[0].name = "TEST2"
        fetched[0].color = .green
        try context.save()
        fetched = try context.fetch(FetchDescriptor<TaskCategory>())
        XCTAssertEqual(fetched[0].name, "TEST2")
        XCTAssertEqual(fetched[0].colorIdentifier, CategoryColor.green.rawValue)
        XCTAssertEqual(fetched[0].color, .green)

        context.delete(fetched[0])
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
    }

    func testEveryCategoryColorIdentifierRoundTripsThroughModel() {
        for color in CategoryColor.allCases {
            let category = TaskCategory(name: color.title, colorIdentifier: color.rawValue)
            XCTAssertEqual(category.colorIdentifier, color.rawValue)
            XCTAssertEqual(category.color, color)
            category.color = color
            XCTAssertEqual(category.colorIdentifier, color.rawValue)
        }
    }

    func testUnknownCategoryColorSafelyMapsToBlue() {
        let category = TaskCategory(name: "Legacy", colorIdentifier: "unknown")
        XCTAssertEqual(category.color, .blue)
    }

    func testWidgetStyleDeletionPersistsImmediately() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let task = TodoTask(title: "Delete from widget")
        let survivor = TodoTask(title: "Keep")
        context.insert(task)
        context.insert(survivor)
        try context.save()

        context.delete(task)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<TodoTask>()).map(\.title), ["Keep"])
    }

    func testCompletionTimestampIsSetAndCleared() {
        let task = TodoTask(title: "Finish")
        let date = Date(timeIntervalSince1970: 1234)
        task.setCompleted(true, at: date)
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completedAt, date)
        task.setCompleted(false, at: date)
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
    }

    func testTaskCanMoveToAnotherDate() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9)))
        let existingTomorrowTask = TodoTask(title: "Tomorrow first", sortOrder: 0, scheduledDate: tomorrow)
        let task = TodoTask(title: "Move me", sortOrder: 0, scheduledDate: today)

        TaskScheduling.move(task, to: tomorrow, among: [existingTomorrowTask, task], calendar: calendar)

        XCTAssertTrue(task.isScheduled(on: tomorrow, calendar: calendar))
        XCTAssertEqual(task.sortOrder, 1)
    }

    func testDailyRepeatCreatesUpcomingOccurrences() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9)))
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let task = TodoTask(title: "Drink water", sortOrder: 0, scheduledDate: today)
        context.insert(task)

        try TaskRepeatScheduler.setRepeatRule(.daily, for: task, tasks: [task], in: context, calendar: calendar)

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        XCTAssertEqual(task.repeatRule, .daily)
        XCTAssertEqual(tasks.filter { $0.isScheduled(on: tomorrow, calendar: calendar) }.count, 1)
    }

    func testNewlyCompletedTaskMovesToFrontOfCompletedTasks() {
        let first = TodoTask(title: "Read paper", sortOrder: 0)
        let second = TodoTask(title: "Reply email", sortOrder: 1)
        let third = TodoTask(title: "Finish report", sortOrder: 2)
        let tasks = [first, second, third]

        second.isCompleted = true
        TaskListOrdering.moveCompletedTaskToFront(second, in: tasks)

        third.isCompleted = true
        TaskListOrdering.moveCompletedTaskToFront(third, in: tasks)

        XCTAssertEqual(
            TaskListOrdering.ordered(tasks).map(\.title),
            ["Read paper", "Finish report", "Reply email"]
        )
    }

    func testPersistentContainerReopensSavedTask() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTODOTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("EasyTODO.store")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        do {
            let container = try PersistenceController.modelContainer(storeURL: storeURL)
            let context = container.mainContext
            context.insert(TodoTask(title: "Persist me", sortOrder: 0))
            try context.save()
        }

        do {
            let container = try PersistenceController.modelContainer(storeURL: storeURL)
            let tasks = try container.mainContext.fetch(FetchDescriptor<TodoTask>())

            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(tasks.first?.title, "Persist me")
        }
    }

    func testPersistentContainerReopensSavedFutureTaskDate() throws {
        let calendar = Calendar.current
        let futureDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 9, hour: 9)))
        let expectedDay = calendar.startOfDay(for: futureDate)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EasyTODOTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directory.appendingPathComponent("EasyTODO.store")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        do {
            let container = try PersistenceController.modelContainer(storeURL: storeURL)
            let context = container.mainContext
            context.insert(TodoTask(title: "Future task", sortOrder: 0, scheduledDate: futureDate))
            try context.save()
        }

        do {
            let container = try PersistenceController.modelContainer(storeURL: storeURL)
            let tasks = try container.mainContext.fetch(FetchDescriptor<TodoTask>())

            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(tasks.first?.scheduledDate, Optional(expectedDay))
            XCTAssertTrue(try XCTUnwrap(tasks.first).isScheduled(on: futureDate, calendar: calendar))
        }
    }

    func testUnfinishedPastTasksRollOverToToday() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9)))
        let yesterday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 9)))
        let todayTask = TodoTask(title: "Already today", sortOrder: 2, scheduledDate: today)
        let overdueTask = TodoTask(title: "Carry forward", sortOrder: 0, scheduledDate: yesterday)
        let completedPastTask = TodoTask(title: "Done yesterday", isCompleted: true, sortOrder: 1, scheduledDate: yesterday)

        let didChange = TaskDayMaintenance.rolloverUnfinishedTasksToToday(
            [todayTask, overdueTask, completedPastTask],
            today: today,
            calendar: calendar
        )

        XCTAssertTrue(didChange)
        XCTAssertTrue(overdueTask.isScheduled(on: today, calendar: calendar))
        XCTAssertEqual(overdueTask.sortOrder, 3)
        XCTAssertTrue(completedPastTask.isScheduled(on: yesterday, calendar: calendar))
    }

    func testTodayAndFutureTasksDoNotRollOver() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 9)))
        let todayTask = TodoTask(title: "Today", scheduledDate: today)
        let futureTask = TodoTask(title: "Future", scheduledDate: tomorrow)

        let didChange = TaskDayMaintenance.rolloverUnfinishedTasksToToday(
            [todayTask, futureTask],
            today: today,
            calendar: calendar
        )

        XCTAssertFalse(didChange)
        XCTAssertTrue(todayTask.isScheduled(on: today, calendar: calendar))
        XCTAssertTrue(futureTask.isScheduled(on: tomorrow, calendar: calendar))
    }
}
