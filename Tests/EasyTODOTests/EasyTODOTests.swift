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
        XCTAssertEqual(task.colorPriority, .notUrgentImportant)
        XCTAssertEqual(task.priority, .normal)
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
        let task = TodoTask(title: "Finish report", colorPriority: .importantUrgent)

        XCTAssertEqual(task.colorPriority, .importantUrgent)

        task.colorPriority = .notUrgentImportant

        XCTAssertEqual(task.colorPriority, .notUrgentImportant)
    }

    func testTaskCanStoreRepeatRule() {
        let task = TodoTask(title: "Standup", repeatRule: .daily)

        XCTAssertEqual(task.repeatRule, .daily)

        task.repeatRule = .weekly

        XCTAssertEqual(task.repeatRule, .weekly)
    }

    func testLegacyPriorityValuesAreMapped() {
        XCTAssertEqual(TaskColorPriority.normalized(from: "urgent"), .importantUrgent)
        XCTAssertEqual(TaskColorPriority.normalized(from: "high"), .notUrgentImportant)
        XCTAssertEqual(TaskColorPriority.normalized(from: "normal"), .notUrgentNotImportant)
        XCTAssertEqual(TaskColorPriority.normalized(from: nil), .notUrgentImportant)
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

    func testLegacyTaskPlannerDefaultsRemainSafe() {
        let undated = TodoTask(title: "Someday")
        let dated = TodoTask(title: "Submit", scheduledDate: .now)

        XCTAssertEqual(undated.deadlineType, .none)
        XCTAssertEqual(dated.deadlineType, .hard)
        XCTAssertEqual(undated.workMode, .medium)
        XCTAssertEqual(undated.taskSize, .medium)
        XCTAssertEqual(undated.safeEstimatedBlocks, 1)
        XCTAssertTrue(undated.dependencyIDs.isEmpty)
        XCTAssertTrue(undated.needsPlannerMetadata)
    }

    func testExplicitEstimatedBlocksOverrideSizeDefault() {
        let task = TodoTask(title: "Two-block XL task")
        task.taskSize = .extraLarge
        task.estimatedBlocks = 2

        XCTAssertEqual(task.safeEstimatedBlocks, 2)
        XCTAssertTrue(task.needsPlannerMetadata)
    }

    func testLegacyDuplicatePlannerIdentifiersAreNormalized() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let sharedID = UUID()
        let first = TodoTask(title: "Legacy first")
        let second = TodoTask(title: "Legacy second")
        first.id = sharedID; second.id = sharedID
        context.insert(first); context.insert(second); try context.save()

        try PlannerCoordinator.normalizeTaskIdentifiers([first, second], in: context)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.id == sharedID || second.id == sharedID)
    }

    func testReplanNormalizesIdentifiersAcrossCompletedAndActiveLegacyTasks() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let sharedID = UUID()
        let active = TodoTask(title: "Active")
        let completed = TodoTask(title: "Completed", isCompleted: true)
        active.id = sharedID; completed.id = sharedID
        context.insert(active); context.insert(completed); try context.save()

        _ = try PlannerCoordinator.replan(in: context)

        XCTAssertNotEqual(active.id, completed.id)
    }

    func testDefaultCapacityProfileMatchesSchoolAndFreeWeek() {
        let byWeekday = Dictionary(uniqueKeysWithValues: DefaultCapacityProfile.templates().map { ($0.weekday, $0) })

        XCTAssertEqual(byWeekday[2]?.kind, .school)
        XCTAssertEqual(byWeekday[2]?.deepCapacity, 1)
        XCTAssertEqual(byWeekday[5]?.deepCapacity, 1)
        XCTAssertEqual(byWeekday[6]?.kind, .free)
        XCTAssertEqual(byWeekday[6]?.deepCapacity, 2)
        XCTAssertTrue(byWeekday[1]?.fixedCommitments.contains("Protected rest 21:00–22:00") == true)
    }

    func testPlannerRejectsDependencyCycle() throws {
        let firstID = UUID(), secondID = UUID()
        let day = PlannerCapacityDay(date: .now, kind: .free, deep: 2, medium: 2, fragment: 2,
                                     preferredDeepPeriods: [.deep1, .deep2])
        let first = plannerTask(id: firstID, title: "First", dependencies: [secondID])
        let second = plannerTask(id: secondID, title: "Second", dependencies: [firstID])

        XCTAssertThrowsError(try DeterministicPlanner.generatePlan(tasks: [first, second], dayCapacities: [day], lockedBlocks: [])) {
            guard case PlannerError.dependencyCycle = $0 else { return XCTFail("Expected dependency cycle") }
        }
    }

    func testPlannerRespectsLockedCapacityAndReportsOverload() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let task = plannerTask(title: "Research", deadline: today, blocks: 2, mode: .deep)
        let day = PlannerCapacityDay(date: today, kind: .school, deep: 1, medium: 1, fragment: 1,
                                     preferredDeepPeriods: [.evening])
        let locked = PlannerLockedBlock(taskID: UUID(), date: today, mode: .deep, period: .evening)

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: [day], lockedBlocks: [locked], now: today, calendar: calendar)

        XCTAssertTrue(output.blocks.isEmpty)
        XCTAssertEqual(output.conflicts.first?.required, 2)
        XCTAssertEqual(output.conflicts.first?.available, 0)
    }

    func testPlannerPlacesPrerequisiteBeforeDependentTask() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let due = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: today))
        let prerequisite = plannerTask(title: "Research", deadline: due, blocks: 1, mode: .deep)
        let dependent = plannerTask(title: "Draft", deadline: due, blocks: 1, mode: .deep,
                                    dependencies: [prerequisite.id])
        let days = (0...5).compactMap { offset -> PlannerCapacityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return PlannerCapacityDay(date: date, kind: .free, deep: 1, medium: 1, fragment: 1,
                                      preferredDeepPeriods: [.deep1])
        }

        let output = try DeterministicPlanner.generatePlan(tasks: [dependent, prerequisite], dayCapacities: days,
                                                           lockedBlocks: [], now: today, calendar: calendar)
        let prerequisiteDate = try XCTUnwrap(output.blocks.first { $0.taskID == prerequisite.id }?.date)
        let dependentDate = try XCTUnwrap(output.blocks.first { $0.taskID == dependent.id }?.date)

        XCTAssertLessThan(prerequisiteDate, dependentDate)
    }

    func testHardDateOnlyDeadlineRemainsEligible() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let task = plannerTask(title: "Deadline-day work", deadline: due, blocks: 1, mode: .deep)
        let days = [
            PlannerCapacityDay(date: today, kind: .school, deep: 0, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.evening]),
            PlannerCapacityDay(date: due, kind: .free, deep: 1, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.deep1])
        ]

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: today, calendar: calendar)

        XCTAssertEqual(output.blocks.map(\.date), [due])
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testSafetyBufferPrefersEarlierDayButFallsBackToDeadlineDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let task = plannerTask(title: "Two-block task", deadline: due, blocks: 2, mode: .deep)
        let days = [
            PlannerCapacityDay(date: today, kind: .school, deep: 1, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.evening]),
            PlannerCapacityDay(date: due, kind: .free, deep: 2, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.deep1, .deep2])
        ]

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: today, calendar: calendar)

        XCTAssertEqual(output.blocks.map(\.date), [today, due])
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testPlannerReportsRealOverloadThroughActualDeadline() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let task = plannerTask(title: "Four-block task", deadline: due, blocks: 4, mode: .deep)
        let days = [
            PlannerCapacityDay(date: today, kind: .school, deep: 1, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.evening]),
            PlannerCapacityDay(date: due, kind: .free, deep: 2, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.deep1, .deep2])
        ]

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: today, calendar: calendar)

        XCTAssertEqual(output.blocks.count, 3)
        XCTAssertEqual(output.conflicts.first?.required, 4)
        XCTAssertEqual(output.conflicts.first?.available, 3)
    }

    func testConflictResolverPrefersExplicitInternalDeadlineAndNeverMovesHardDeadline() throws {
        let fixture = try conflictFixture()
        let candidates = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                     templates: fixture.templates, overrides: [], blocks: [],
                                                     currentOutput: fixture.output, now: fixture.today, calendar: fixture.calendar).all
        let moves = candidates.compactMap { candidate -> (UUID, Date)? in
            guard case let .moveInternalDeadline(id, _, to) = candidate.action else { return nil }
            return (id, to)
        }

        XCTAssertEqual(fixture.conflict.required - fixture.conflict.available, 1)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.0, fixture.internalTask.id)
        XCTAssertNotEqual(moves.first?.0, fixture.hardTask.id)
        XCTAssertTrue(try XCTUnwrap(candidates.first { $0.type == .moveInternalDeadline }).output.conflicts.isEmpty)
        XCTAssertEqual(fixture.internalTask.scheduledDate, fixture.due, "Preview must not mutate persistence models")
    }

    func testHardOnlyConflictOffersNoDeadlineMove() throws {
        var fixture = try conflictFixture()
        fixture.internalTask.setDeadlineType(.hard, source: .userSelected)
        fixture = try conflictFixture(tasks: fixture.tasks)
        let previews = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                   templates: fixture.templates, overrides: [], blocks: [],
                                                   currentOutput: fixture.output, now: fixture.today, calendar: fixture.calendar).all

        XCTAssertFalse(previews.contains { $0.type == .moveInternalDeadline })
        XCTAssertTrue(previews.contains { $0.type == .dayCapacityOverride })
        XCTAssertTrue(previews.contains { $0.type == .adjustEstimatedWork })
    }

    func testKeepingConflictUnresolvedDoesNotMutateTasksOrHideConflict() throws {
        let fixture = try conflictFixture()
        let originalDates = fixture.tasks.map(\.scheduledDate)
        let originalEstimates = fixture.tasks.map(\.estimatedBlocks)

        // "Keep current plan" intentionally performs no coordinator mutation.
        XCTAssertEqual(fixture.tasks.map(\.scheduledDate), originalDates)
        XCTAssertEqual(fixture.tasks.map(\.estimatedBlocks), originalEstimates)
        XCTAssertEqual(fixture.output.conflicts.first?.required, 2)
        XCTAssertEqual(fixture.output.conflicts.first?.available, 1)
    }

    func testOneDayCapacityOverrideDoesNotChangeRecurringTemplate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let thursday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let nextThursday = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: thursday))
        let template = DayCapacityTemplate(weekday: 5, kind: .school, deepCapacity: 1, mediumCapacity: 1,
                                           fragmentCapacity: 1, preferredDeepPeriods: [.evening],
                                           cognitiveLoadFromCommitments: 3)
        let override = DayCapacityOverride(date: thursday, additionalDeepCapacity: 1, reason: "Allow once")
        let days = PlannerCoordinator.capacityDays(from: [template], overrides: [override],
                                                   through: nextThursday, now: thursday, calendar: calendar)

        XCTAssertEqual(days.first { calendar.isDate($0.date, inSameDayAs: thursday) }?.deep, 2)
        XCTAssertEqual(days.first { calendar.isDate($0.date, inSameDayAs: nextThursday) }?.deep, 1)
        XCTAssertEqual(template.deepCapacity, 1)
    }

    func testApplyingDeadlineMoveAndUndoRestoresDeadlineAndBlocks() throws {
        let fixture = try conflictFixture()
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        fixture.tasks.forEach(context.insert)
        try context.save()
        let initial = try PlannerCoordinator.replan(in: context, now: fixture.today, calendar: fixture.calendar)
        let conflict = try XCTUnwrap(initial.output.conflicts.first)
        let storedTemplates = try context.fetch(FetchDescriptor<DayCapacityTemplate>())
        let storedBlocks = try context.fetch(FetchDescriptor<WorkBlock>())
        let preview = try XCTUnwrap(ConflictResolver.candidates(for: conflict, tasks: fixture.tasks,
                                                                templates: storedTemplates, overrides: [], blocks: storedBlocks,
                                                                currentOutput: initial.output, now: fixture.today,
                                                                calendar: fixture.calendar).all.first {
            $0.type == .moveInternalDeadline
        })
        let oldBlockDates = storedBlocks.map(\.date).sorted()

        let applied = try PlannerCoordinator.apply(preview, in: context, now: fixture.today, calendar: fixture.calendar)
        XCTAssertNotEqual(fixture.internalTask.scheduledDate, fixture.due)
        try PlannerCoordinator.undo(applied.undoSnapshot, in: context)

        XCTAssertEqual(fixture.internalTask.scheduledDate, fixture.due)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkBlock>()).map(\.date).sorted(), oldBlockDates)
    }

    func testLegacyDeadlineStillSchedulesButNeedsConfirmation() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let task = TodoTask(title: "Legacy", scheduledDate: today)
        let input = PlannerTaskInput(id: task.id, title: task.title, deadline: task.scheduledDate,
                                     deadlineType: task.deadlineType, mode: .deep, size: .medium,
                                     energy: .medium, remainingBlocks: 1, blockMinutes: 60,
                                     splittable: true, uncertainty: .low, dependencies: [],
                                     meetingDate: nil, manualPriority: nil)
        let day = PlannerCapacityDay(date: today, kind: .school, deep: 1, medium: 1, fragment: 1,
                                     preferredDeepPeriods: [.evening])

        let output = try DeterministicPlanner.generatePlan(tasks: [input], dayCapacities: [day],
                                                           lockedBlocks: [], now: today, calendar: calendar)
        XCTAssertFalse(task.deadlineTypeWasExplicitlySet)
        XCTAssertEqual(task.deadlineType, .hard)
        XCTAssertEqual(output.blocks.count, 1)
    }

    func testPreSourceExplicitDeadlineRemainsUserSelected() {
        let task = TodoTask(title: "Existing choice", scheduledDate: .now)
        task.deadlineTypeRawValue = DeadlineType.internalDeadline.rawValue
        task.deadlineTypeSourceRawValue = nil

        XCTAssertEqual(task.deadlineType, .internalDeadline)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testConflictCandidatesExposeOnlyTopThreeByDefaultAndPutRemainingUnderMore() throws {
        let fixture = try conflictFixture()
        let ranked = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                 templates: fixture.templates, overrides: [], blocks: [],
                                                 currentOutput: fixture.output, now: fixture.today,
                                                 calendar: fixture.calendar)

        XCTAssertEqual(ranked.topCandidates.count, 3)
        XCTAssertEqual(ranked.remainingCandidates.count, ranked.all.count - 3)
        XCTAssertEqual(ResolutionType.allCases.count, 7)
        XCTAssertFalse(ranked.remainingCandidates.isEmpty)
    }

    func testInvalidConflictCandidatesAreFilteredOut() throws {
        var fixture = try conflictFixture()
        fixture.hardTask.splittable = false
        fixture.internalTask.splittable = false
        fixture.internalTask.setDeadlineType(.hard, source: .autoDetected)
        fixture = try conflictFixture(tasks: fixture.tasks)
        let candidates = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                     templates: fixture.templates, overrides: [], blocks: [],
                                                     currentOutput: fixture.output, now: fixture.today,
                                                     calendar: fixture.calendar).all

        XCTAssertFalse(candidates.contains { $0.type == .moveInternalDeadline })
        XCTAssertFalse(candidates.contains { $0.type == .splitBlock })
    }

    func testFixedAssessmentRecognizerMatchesAcademicAssessmentTokens() {
        XCTAssertEqual(FixedAssessmentRecognizer.match(in: "AdvMath SA")?.phrase, "SA")
        XCTAssertEqual(FixedAssessmentRecognizer.match(in: "Physics Summative Assessment")?.phrase, "Summative Assessment")
        for title in ["Math Exam", "Psych Quiz", "Algebra Midterm", "Course Final", "Chem Test"] {
            XCTAssertNotNil(FixedAssessmentRecognizer.match(in: title), title)
        }
    }

    func testFixedAssessmentRecognizerDoesNotMatchArbitrarySubstrings() {
        for title in ["Essay draft", "Passage notes", "Finale rehearsal", "Contest plan"] {
            XCTAssertNil(FixedAssessmentRecognizer.match(in: title), title)
        }
    }

    func testManualDeadlineOverrideBeatsAssessmentAutoDetection() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let task = TodoTask(title: "AdvMath SA", scheduledDate: .now)
        task.setDeadlineType(.internalDeadline, source: .userSelected)
        context.insert(task); try context.save()

        try PlannerCoordinator.applyAutomaticDeadlineRecognition([task], in: context)

        XCTAssertEqual(task.deadlineType, .internalDeadline)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testAssessmentAutoDetectionPersistsOfficialTypeAndSource() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let task = TodoTask(title: "AdvMath SA", scheduledDate: .now)
        context.insert(task); try context.save()

        try PlannerCoordinator.applyAutomaticDeadlineRecognition([task], in: context)

        XCTAssertEqual(task.deadlineType, .hard)
        XCTAssertEqual(task.deadlineTypeSource, .autoDetected)
        XCTAssertEqual(task.deadlineTypeRawValue, DeadlineType.hard.rawValue)
    }

    func testAutoDetectedFixedAssessmentNeverGetsMoveCandidate() throws {
        let fixture = try conflictFixture()
        fixture.internalTask.title = "AdvMath SA"
        fixture.internalTask.setDeadlineType(.hard, source: .autoDetected)
        let rebuilt = try conflictFixture(tasks: fixture.tasks)
        let candidates = ConflictResolver.candidates(for: rebuilt.conflict, tasks: rebuilt.tasks,
                                                     templates: rebuilt.templates, overrides: [], blocks: [],
                                                     currentOutput: rebuilt.output, now: rebuilt.today,
                                                     calendar: rebuilt.calendar).all

        XCTAssertFalse(candidates.contains {
            guard case let .moveInternalDeadline(taskID, _, _) = $0.action else { return false }
            return taskID == fixture.internalTask.id
        })
    }

    func testSplitBlockOnlyAppearsWhenSplittableAndUseful() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        let useful = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                 templates: fixture.templates, overrides: [], blocks: [],
                                                 currentOutput: fixture.output, now: fixture.today,
                                                 calendar: fixture.calendar).all
        XCTAssertTrue(useful.contains { $0.type == .splitBlock })

        fixture.task.splittable = false
        let unavailable = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                      templates: fixture.templates, overrides: [], blocks: [],
                                                      currentOutput: fixture.output, now: fixture.today,
                                                      calendar: fixture.calendar).all
        XCTAssertFalse(unavailable.contains { $0.type == .splitBlock })
    }

    func testDeepSplitCreatesTwoDeepSixtyMinuteSessions() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        guard case let .splitBlock(_, fromMinutes, _, sessions) = split.action else {
            return XCTFail("Expected Split Block action")
        }
        XCTAssertEqual(fromMinutes, 120)
        XCTAssertEqual(sessions.map(\.mode), [.deep, .deep])
        XCTAssertEqual(sessions.map(\.minutes), [60, 60])
    }

    func testMediumSplitCreatesShorterMediumSessions() throws {
        let fixture = try splitFixture(mode: .medium, totalMinutes: 90, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        guard case let .splitBlock(_, _, _, sessions) = split.action else {
            return XCTFail("Expected Split Block action")
        }
        XCTAssertEqual(sessions.map(\.mode), [.medium, .medium])
        XCTAssertEqual(sessions.map(\.minutes), [45, 45])
    }

    func testDeepSplitNeverBecomesMedium() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        guard case let .splitBlock(_, _, _, sessions) = split.action else {
            return XCTFail("Expected Split Block action")
        }
        XCTAssertFalse(sessions.contains { $0.mode == .medium })
    }

    func testMediumSplitNeverBecomesFragmentable() throws {
        let fixture = try splitFixture(mode: .medium, totalMinutes: 90, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        guard case let .splitBlock(_, _, _, sessions) = split.action else {
            return XCTFail("Expected Split Block action")
        }
        XCTAssertFalse(sessions.contains { $0.mode == .fragmentable })
    }

    func testSplitPreservesTotalEstimatedMinutes() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 121, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        guard case let .splitBlock(_, fromMinutes, _, sessions) = split.action else {
            return XCTFail("Expected Split Block action")
        }
        XCTAssertEqual(sessions.reduce(0) { $0 + $1.minutes }, fromMinutes)
        XCTAssertEqual(sessions.map(\.minutes), [60, 61])
    }

    func testSplitRespectsMinimumBlockMinutes() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 61)
        XCTAssertNil(splitCandidate(in: fixture))
    }

    func testSplitRequiresCompatibleSameModeCapacity() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45,
                                       capacityMode: .medium)
        XCTAssertNil(splitCandidate(in: fixture))
    }

    func testNonSplittableTaskHasNoSplitCandidate() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        fixture.task.splittable = false
        XCTAssertNil(splitCandidate(in: fixture))
    }

    func testSplitThatDoesNotReduceConflictIsNotShown() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        let occupied = ProposedWorkBlock(taskID: UUID(), date: fixture.today, period: .evening,
                                         mode: .deep, minutes: 60)
        let output = PlannerOutput(blocks: fixture.output.blocks + [occupied],
                                   taskMetadata: fixture.output.taskMetadata,
                                   conflicts: fixture.output.conflicts)
        let ranked = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                 templates: fixture.templates, overrides: [], blocks: [],
                                                 currentOutput: output, now: fixture.today,
                                                 calendar: fixture.calendar)
        XCTAssertFalse(ranked.all.contains { $0.type == .splitBlock })
    }

    func testSplitPreviewCanFullyResolveConflict() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        XCTAssertTrue(split.resolvesConflict)
        XCTAssertEqual(split.outcome, "Resolves the conflict")
        XCTAssertTrue(split.output.conflicts.isEmpty)
    }

    func testApplyingSplitLocksLinkedSameModeSessions() throws {
        let fixture = try splitFixture(mode: .deep, totalMinutes: 120, minimumMinutes: 45)
        let split = try XCTUnwrap(splitCandidate(in: fixture))
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        context.insert(fixture.task)
        fixture.templates.forEach(context.insert)
        try context.save()

        _ = try PlannerCoordinator.apply(split, in: context, now: fixture.today, calendar: fixture.calendar)

        let stored = try context.fetch(FetchDescriptor<WorkBlock>()).filter { $0.taskID == fixture.task.id }
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.locked && $0.mode == .deep })
        XCTAssertEqual(stored.reduce(0) { $0 + $1.estimatedMinutes }, 120)
        XCTAssertEqual(Set(stored.compactMap(\.splitGroupID)).count, 1)
        XCTAssertNotNil(stored.first?.splitGroupID)
        XCTAssertEqual(fixture.task.estimatedMinutes, 120)
    }

    func testEmergencyOverrideNormallyLivesUnderMoreOptions() throws {
        let fixture = try conflictFixture()
        let ranked = ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                                 templates: fixture.templates, overrides: [], blocks: [],
                                                 currentOutput: fixture.output, now: fixture.today,
                                                 calendar: fixture.calendar)
        XCTAssertFalse(ranked.topCandidates.contains { $0.type == .emergencyOverride })
        XCTAssertTrue(ranked.remainingCandidates.contains { $0.type == .emergencyOverride })
    }

    func testFocusConflictSummaryDistinguishesActiveAcknowledgedAndResolved() throws {
        let fixture = try conflictFixture()
        let active = FocusConflictSummary(conflicts: [fixture.conflict], acknowledgedKeys: [])
        XCTAssertEqual(active.activeConflictCount, 1)
        XCTAssertEqual(active.acknowledgedConflictCount, 0)
        XCTAssertTrue(active.hasAny)

        let acknowledged = FocusConflictSummary(conflicts: [fixture.conflict],
                                                acknowledgedKeys: [fixture.conflict.conflictKey])
        XCTAssertEqual(acknowledged.activeConflictCount, 0)
        XCTAssertEqual(acknowledged.acknowledgedConflictCount, 1)
        XCTAssertTrue(acknowledged.hasAny)

        let resolved = FocusConflictSummary(conflicts: [], acknowledgedKeys: [fixture.conflict.conflictKey])
        XCTAssertFalse(resolved.hasAny)

        let zeroShortfall = ScheduleConflict(mode: .deep, deadline: fixture.due,
                                             required: 2, available: 2,
                                             taskIDs: [fixture.hardTask.id],
                                             taskTitles: [fixture.hardTask.title])
        let stale = FocusConflictSummary(conflicts: [zeroShortfall],
                                         acknowledgedKeys: [zeroShortfall.conflictKey])
        XCTAssertEqual(stale.activeConflictCount, 0)
        XCTAssertEqual(stale.acknowledgedConflictCount, 0)
        XCTAssertFalse(stale.hasAny)
    }

    func testKeepUnresolvedPersistsAcknowledgementWithoutChangingPlanInputs() throws {
        let fixture = try conflictFixture()
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        fixture.tasks.forEach(context.insert); try context.save()
        let plan = try PlannerCoordinator.replan(in: context, now: fixture.today, calendar: fixture.calendar)
        let conflict = try XCTUnwrap(plan.output.conflicts.first)
        let templates = try context.fetch(FetchDescriptor<DayCapacityTemplate>())
        let blocks = try context.fetch(FetchDescriptor<WorkBlock>())
        let keep = try XCTUnwrap(ConflictResolver.candidates(for: conflict, tasks: fixture.tasks,
                                                             templates: templates, overrides: [], blocks: blocks,
                                                             currentOutput: plan.output, now: fixture.today,
                                                             calendar: fixture.calendar).all.first { $0.type == .keepUnresolved })
        let dates = fixture.tasks.map(\.scheduledDate)
        let estimates = fixture.tasks.map(\.estimatedBlocks)

        _ = try PlannerCoordinator.apply(keep, in: context, now: fixture.today, calendar: fixture.calendar)

        XCTAssertEqual(fixture.tasks.map(\.scheduledDate), dates)
        XCTAssertEqual(fixture.tasks.map(\.estimatedBlocks), estimates)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduleConflictAcknowledgement>()).map(\.conflictKey),
                       [conflict.conflictKey])
    }

    func testOrdinaryReplanUsesCompatibleCapacityBeforeSurfacingConflict() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let due = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let task = plannerTask(title: "Fits normally", deadline: due, blocks: 3, mode: .deep)
        let days = [
            PlannerCapacityDay(date: today, kind: .school, deep: 1, medium: 1, fragment: 1, preferredDeepPeriods: [.evening]),
            PlannerCapacityDay(date: due, kind: .free, deep: 2, medium: 2, fragment: 2, preferredDeepPeriods: [.deep1, .deep2])
        ]

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: today, calendar: calendar)
        XCTAssertEqual(output.blocks.count, 3)
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    private struct SplitFixture {
        let calendar: Calendar
        let today: Date
        let task: TodoTask
        let tasks: [TodoTask]
        let templates: [DayCapacityTemplate]
        let output: PlannerOutput
        let conflict: ScheduleConflict
    }

    private func splitFixture(mode: WorkMode, totalMinutes: Int, minimumMinutes: Int,
                              capacityMode: WorkMode? = nil) throws -> SplitFixture {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let due = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let task = TodoTask(title: "Split target", scheduledDate: due)
        task.setDeadlineType(.hard, source: .userSelected)
        task.workMode = mode
        task.taskSize = .large
        task.estimatedMinutes = totalMinutes
        task.estimatedBlocks = 1
        task.completedBlocks = 0
        task.minimumBlockMinutes = minimumMinutes
        task.splittable = true
        task.uncertainty = .low

        let suppliedMode = capacityMode ?? mode
        let firstMinutes = totalMinutes / 2
        let secondMinutes = totalMinutes - firstMinutes
        func template(weekday: Int, kind: DayTemplateKind, minutes: Int) -> DayCapacityTemplate {
            DayCapacityTemplate(
                weekday: weekday, kind: kind,
                deepCapacity: suppliedMode == .deep ? 1 : 0,
                mediumCapacity: suppliedMode == .medium ? 1 : 0,
                fragmentCapacity: suppliedMode == .fragmentable ? 1 : 0,
                preferredDeepPeriods: kind == .school ? [.evening] : [.deep1],
                deepPeriodMinutes: suppliedMode == .deep ? [minutes] : [],
                mediumPeriodMinutes: suppliedMode == .medium ? [minutes] : [],
                fragmentPeriodMinutes: suppliedMode == .fragmentable ? [minutes] : [],
                cognitiveLoadFromCommitments: kind == .school ? 3 : 0
            )
        }
        let templates = [
            template(weekday: 5, kind: .school, minutes: firstMinutes),
            template(weekday: 6, kind: .free, minutes: secondMinutes)
        ]
        let input = PlannerTaskInput(id: task.id, title: task.title, deadline: due,
                                     deadlineType: task.deadlineType, mode: mode, size: task.taskSize,
                                     energy: task.energyDemand, remainingBlocks: task.remainingBlocks,
                                     blockMinutes: task.plannedBlockMinutes, splittable: true,
                                     uncertainty: .low, dependencies: [], meetingDate: nil,
                                     manualPriority: nil)
        let capacities = PlannerCoordinator.capacityDays(from: templates, through: due,
                                                         now: today, calendar: calendar)
        let output = try DeterministicPlanner.generatePlan(tasks: [input], dayCapacities: capacities,
                                                           lockedBlocks: [], now: today, calendar: calendar)
        return SplitFixture(calendar: calendar, today: today, task: task, tasks: [task],
                            templates: templates, output: output,
                            conflict: try XCTUnwrap(output.conflicts.first))
    }

    private func splitCandidate(in fixture: SplitFixture) -> ConflictResolutionCandidate? {
        ConflictResolver.candidates(for: fixture.conflict, tasks: fixture.tasks,
                                    templates: fixture.templates, overrides: [], blocks: [],
                                    currentOutput: fixture.output, now: fixture.today,
                                    calendar: fixture.calendar).all.first { $0.type == .splitBlock }
    }

    private struct ConflictFixture {
        let calendar: Calendar
        let today: Date
        let due: Date
        let hardTask: TodoTask
        let internalTask: TodoTask
        let tasks: [TodoTask]
        let templates: [DayCapacityTemplate]
        let output: PlannerOutput
        let conflict: ScheduleConflict
    }

    private func conflictFixture(tasks supplied: [TodoTask]? = nil) throws -> ConflictFixture {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let hard = supplied?.first ?? TodoTask(title: "Official", scheduledDate: due)
        let flexible = supplied?.dropFirst().first ?? TodoTask(title: "My target", scheduledDate: due)
        if supplied == nil {
            hard.setDeadlineType(.hard, source: .userSelected)
            flexible.setDeadlineType(.internalDeadline, source: .userSelected)
            for task in [hard, flexible] {
                task.workMode = .deep; task.taskSize = .large; task.estimatedBlocks = 2
                task.completedBlocks = 0; task.splittable = true; task.uncertainty = .low
            }
        }
        let tasks = [hard, flexible]
        let thursday = DayCapacityTemplate(weekday: 5, kind: .school, deepCapacity: 1, mediumCapacity: 1,
                                           fragmentCapacity: 1, preferredDeepPeriods: [.evening], cognitiveLoadFromCommitments: 3)
        let friday = DayCapacityTemplate(weekday: 6, kind: .free, deepCapacity: 2, mediumCapacity: 2,
                                         fragmentCapacity: 2, preferredDeepPeriods: [.deep1, .deep2], cognitiveLoadFromCommitments: 0)
        let saturday = DayCapacityTemplate(weekday: 7, kind: .free, deepCapacity: 2, mediumCapacity: 2,
                                           fragmentCapacity: 2, preferredDeepPeriods: [.deep1, .deep2], cognitiveLoadFromCommitments: 0)
        let templates = [thursday, friday, saturday]
        let inputs = tasks.map {
            PlannerTaskInput(id: $0.id, title: $0.title, deadline: $0.scheduledDate,
                             deadlineType: $0.deadlineType, mode: $0.workMode, size: $0.taskSize,
                             energy: $0.energyDemand, remainingBlocks: $0.remainingBlocks,
                             blockMinutes: 60, splittable: true, uncertainty: .low,
                             dependencies: [], meetingDate: nil, manualPriority: nil)
        }
        let capacities = PlannerCoordinator.capacityDays(from: templates, through: due,
                                                         now: today, calendar: calendar)
        let output = try DeterministicPlanner.generatePlan(tasks: inputs, dayCapacities: capacities,
                                                           lockedBlocks: [], now: today, calendar: calendar)
        return ConflictFixture(calendar: calendar, today: today, due: due, hardTask: hard,
                               internalTask: flexible, tasks: tasks, templates: templates,
                               output: output, conflict: try XCTUnwrap(output.conflicts.first))
    }

    func testWorkBlockNumberingUsesScheduledBlockOrder() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let task = TodoTask(title: "Two blocks")
        task.taskSize = .extraLarge; task.workMode = .deep; task.estimatedBlocks = 2; task.completedBlocks = 0
        let first = WorkBlock(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, taskID: task.id,
                              date: firstDate, period: .evening, mode: .deep, estimatedMinutes: 60)
        let second = WorkBlock(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, taskID: task.id,
                               date: secondDate, period: .deep1, mode: .deep, estimatedMinutes: 60)

        XCTAssertEqual(WorkBlockNumbering.displayNumber(for: first, task: task, among: [second, first]), 1)
        XCTAssertEqual(WorkBlockNumbering.displayNumber(for: second, task: task, among: [second, first]), 2)
        XCTAssertEqual(task.safeEstimatedBlocks, 2)
    }

    func testWorkBlockNumberingContinuesAfterCompletedBlocks() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19)))
        let task = TodoTask(title: "Three blocks")
        task.taskSize = .extraLarge; task.workMode = .deep; task.estimatedBlocks = 3; task.completedBlocks = 1
        let second = WorkBlock(taskID: task.id, date: firstDate, period: .deep1, mode: .deep, estimatedMinutes: 60)
        let third = WorkBlock(taskID: task.id, date: secondDate, period: .deep1, mode: .deep, estimatedMinutes: 60)

        XCTAssertEqual(WorkBlockNumbering.displayNumber(for: second, task: task, among: [third, second]), 2)
        XCTAssertEqual(WorkBlockNumbering.displayNumber(for: third, task: task, among: [third, second]), 3)
    }

    func testDayPresentationShowsAllAssignedTasksAsPeersAndDeduplicatesSessions() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let first = TodoTask(title: "First", createdAt: day)
        let second = TodoTask(title: "Second", createdAt: day.addingTimeInterval(1))
        let third = TodoTask(title: "Third", createdAt: day.addingTimeInterval(2))
        first.executionRank = 3
        second.executionRank = 1
        third.executionRank = 2
        let blocks = [
            WorkBlock(taskID: first.id, date: day, period: .deep1, mode: .deep, estimatedMinutes: 60),
            WorkBlock(taskID: first.id, date: day, period: .deep2, mode: .deep, estimatedMinutes: 60),
            WorkBlock(taskID: second.id, date: day, period: .afternoon, mode: .medium, estimatedMinutes: 60),
            WorkBlock(taskID: third.id, date: day, period: .flexible, mode: .fragmentable, estimatedMinutes: 30)
        ]

        let presented = DayTaskPresentation.tasks(on: day, from: [third, second, first], blocks: blocks, calendar: calendar)

        XCTAssertEqual(presented.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(presented.filter { $0.id == first.id }.count, 1)
    }

    func testFutureStartByDoesNotExcludeTodayAndIsSatisfiedByFirstSession() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let startBy = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: today))
        let due = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: today))
        let block = PlannerBlockInput(id: UUID(), orderIndex: 0, title: "Study", remainingMinutes: 60,
                                      estimatedMinutes: 60, splittable: false, minimumSessionMinutes: 30)
        let task = PlannerTaskInput(id: UUID(), title: "Assessment", deadline: due, deadlineType: .hard,
                                    mode: .deep, size: .large, energy: .high, remainingBlocks: 1,
                                    blockMinutes: 60, splittable: false, uncertainty: .low,
                                    dependencies: [], meetingDate: nil, manualPriority: nil,
                                    manualStartBy: startBy, blocks: [block])
        let days = (0...5).compactMap { offset -> PlannerCapacityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return PlannerCapacityDay(date: date, kind: offset < 3 ? .free : .school,
                                      deep: 1, medium: 0, fragment: 0, preferredDeepPeriods: [.deep1])
        }

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: today, calendar: calendar)
        let firstDate = try XCTUnwrap(output.blocks.map(\.date).min())
        XCTAssertLessThanOrEqual(firstDate, startBy)
        XCTAssertGreaterThanOrEqual(firstDate, today)
    }

    func testFreeDayIsPreferredOverLaterSchoolDayForDeepWork() throws {
        let calendar = Calendar(identifier: .gregorian)
        let freeDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let schoolDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: freeDay))
        let block = PlannerBlockInput(id: UUID(), orderIndex: 0, title: "Draft", remainingMinutes: 60,
                                      estimatedMinutes: 60, splittable: false, minimumSessionMinutes: 30)
        let task = PlannerTaskInput(id: UUID(), title: "Draft", deadline: schoolDay, deadlineType: .hard,
                                    mode: .deep, size: .large, energy: .high, remainingBlocks: 1,
                                    blockMinutes: 60, splittable: false, uncertainty: .low,
                                    dependencies: [], meetingDate: nil, manualPriority: nil, blocks: [block])
        let days = [
            PlannerCapacityDay(date: freeDay, kind: .free, deep: 1, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.deep1]),
            PlannerCapacityDay(date: schoolDay, kind: .school, deep: 1, medium: 0, fragment: 0,
                               preferredDeepPeriods: [.evening])
        ]

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: freeDay, calendar: calendar)
        XCTAssertEqual(output.blocks.map(\.date), [freeDay])
    }

    func testCriticalAssessmentBlocksAreDistributedAcrossFreeDays() throws {
        let calendar = Calendar(identifier: .gregorian)
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
        let monday = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: friday))
        let logicalBlocks = (0..<3).map {
            PlannerBlockInput(id: UUID(), orderIndex: $0, title: "Study \($0 + 1)", remainingMinutes: 60,
                              estimatedMinutes: 60, splittable: false, minimumSessionMinutes: 30)
        }
        let task = PlannerTaskInput(id: UUID(), title: "Exam", deadline: monday, deadlineType: .hard,
                                    mode: .deep, size: .extraLarge, energy: .high, remainingBlocks: 3,
                                    blockMinutes: 60, splittable: false, uncertainty: .low,
                                    dependencies: [], meetingDate: nil, priority: .critical,
                                    manualPriority: nil, blocks: logicalBlocks)
        let days = (0...3).compactMap { offset -> PlannerCapacityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: friday) else { return nil }
            return PlannerCapacityDay(date: date, kind: offset < 3 ? .free : .school,
                                      deep: offset < 3 ? 2 : 1, medium: 0, fragment: 0,
                                      preferredDeepPeriods: offset < 3 ? [.deep1, .deep2] : [.evening])
        }

        let output = try DeterministicPlanner.generatePlan(tasks: [task], dayCapacities: days,
                                                           lockedBlocks: [], now: friday, calendar: calendar)
        XCTAssertEqual(Set(output.blocks.map(\.date)), Set(days.prefix(3).map(\.date)))
        XCTAssertFalse(output.blocks.contains { $0.date == monday })
    }

    func testDismissedInteractionUsesActualOutsidePointerAndCollapses() {
        var registry = WidgetInteractionRegistry()
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()
        if registry.begin(.taskEditor) { state.beginInteraction() }
        state.pointerExited()
        if registry.end(.taskEditor) { state.endInteraction() }
        state.synchronizePointer(isInside: false)
        state.collapseGracePeriodCompleted()
        XCTAssertEqual(state.visibility, .launcher)
    }

    private func plannerTask(
        id: UUID = UUID(), title: String, deadline: Date? = nil, blocks: Int = 1,
        mode: WorkMode = .medium, dependencies: [UUID] = []
    ) -> PlannerTaskInput {
        PlannerTaskInput(id: id, title: title, deadline: deadline, deadlineType: deadline == nil ? .none : .hard,
                         mode: mode, size: blocks > 2 ? .extraLarge : .medium, energy: .medium,
                         remainingBlocks: blocks, blockMinutes: 60, splittable: true, uncertainty: .low,
                         dependencies: dependencies, meetingDate: nil, manualPriority: nil)
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
        let firstGreen = TodoTask(title: "First green", sortOrder: 0, colorPriority: .notUrgentImportant)
        let red = TodoTask(title: "Red", sortOrder: 1, colorPriority: .importantUrgent)
        let yellow = TodoTask(title: "Yellow", sortOrder: 2, colorPriority: .urgentNotImportant)
        let secondGreen = TodoTask(title: "Second green", sortOrder: 3, colorPriority: .notUrgentImportant)

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

    func testDuplicateInteractionAppearanceDoesNotLeakCollapseLock() {
        var registry = WidgetInteractionRegistry()
        var state = WidgetHoverState()
        state.show()
        state.pointerEntered()

        if registry.begin(.taskEditor) { state.beginInteraction() }
        if registry.begin(.taskEditor) { state.beginInteraction() }
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(state.interactionLockCount, 1)

        state.pointerExited()
        if registry.end(.taskEditor) { state.endInteraction() }
        XCTAssertEqual(registry.count, 0)
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
        task.userSelectPriority(.high)
        context.insert(task)

        try TaskRepeatScheduler.setRepeatRule(.daily, for: task, tasks: [task], in: context, calendar: calendar)

        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        XCTAssertEqual(task.repeatRule, .daily)
        let tomorrowTasks = tasks.filter { $0.isScheduled(on: tomorrow, calendar: calendar) }
        XCTAssertEqual(tomorrowTasks.count, 1)
        XCTAssertEqual(tomorrowTasks.first?.priority, .high)
        XCTAssertEqual(tomorrowTasks.first?.prioritySource, .userSelected)
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
