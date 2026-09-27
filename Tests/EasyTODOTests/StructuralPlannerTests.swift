import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class StructuralPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Taipei")!; return value
    }

    func testManualStartByOverridesRecommendationAndCanBeCleared() {
        let task = TodoTask(title: "Exam"); task.startBy = date(18); task.manualStartBy = date(17)
        XCTAssertEqual(task.effectiveStartBy, date(17)); task.manualStartBy = nil
        XCTAssertEqual(task.effectiveStartBy, date(18))
    }

    func testManualStartByPlacesFirstSessionNoLaterThanConstraint() throws {
        let input = explicitTask(blocks: [block(0, 60)], manualStartBy: date(17))
        let output = try plan(input, days: [capacity(17, [60]), capacity(18, [60])])
        XCTAssertLessThanOrEqual(try XCTUnwrap(output.blocks.first?.date), date(17))
    }

    func testImpossibleManualStartBySurfacesConflict() throws {
        let input = explicitTask(blocks: [block(0, 60)], manualStartBy: date(17))
        let output = try plan(input, days: [capacity(18, [60])])
        XCTAssertEqual(output.conflicts.first?.reason, .manualStartBy)
    }

    func testPastManualStartByTriggersImmediateCatchUpInsteadOfPermanentConflict() throws {
        let input = explicitTask(blocks: [block(0, 120)], priority: .critical,
                                 manualStartBy: date(17))
        let output = try DeterministicPlanner.generatePlan(
            tasks: [input], dayCapacities: [capacity(18, [120])],
            lockedBlocks: [], now: date(18), calendar: calendar
        )
        XCTAssertEqual(output.blocks.reduce(0) { $0 + $1.minutes }, 120)
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testCriticalOfficialDeepWorkCanUseBoundedFreeDayFlexCapacity() throws {
        let input = explicitTask(blocks: [block(0, 120), block(1, 120), block(2, 120)],
                                 priority: .critical)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [input], dayCapacities: [capacity(17, [120])],
            lockedBlocks: [], now: date(17), calendar: calendar
        )
        XCTAssertEqual(output.blocks.reduce(0) { $0 + $1.minutes }, 360)
        XCTAssertTrue(output.blocks.allSatisfy { $0.mode == .deep })
        XCTAssertFalse(output.blocks.contains { $0.period == .evening || $0.period == .flexible })
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testCriticalFreeDayFlexDoesNotLeakToNormalTask() throws {
        let critical = explicitTask(title: "Official exam", blocks: [block(0, 120)], priority: .critical)
        let normal = explicitTask(title: "Ordinary draft", blocks: [block(0, 120)], priority: .normal)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [normal, critical], dayCapacities: [capacity(17, [120])],
            lockedBlocks: [], now: date(17), calendar: calendar
        )
        XCTAssertEqual(Set(output.blocks.map(\.taskID)), Set([critical.id, normal.id]))
        XCTAssertEqual(output.blocks.first { $0.taskID == normal.id }?.period, .deep1)
        XCTAssertEqual(output.blocks.first { $0.taskID == critical.id }?.period, .afternoon)
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testCriticalInternalDeadlineDoesNotReceiveOfficialFlexCapacity() throws {
        let blocks = [block(0, 120), block(1, 120)]
        let input = PlannerTaskInput(
            id: UUID(), title: "Self-set study", deadline: date(18), deadlineType: .internalDeadline,
            mode: .deep, size: .large, energy: .high, remainingBlocks: blocks.count,
            blockMinutes: 120, splittable: true, uncertainty: .low, dependencies: [],
            meetingDate: nil, priority: .critical, manualPriority: nil, blocks: blocks
        )
        let output = try DeterministicPlanner.generatePlan(
            tasks: [input], dayCapacities: [capacity(17, [120])],
            lockedBlocks: [], now: date(17), calendar: calendar
        )
        XCTAssertEqual(output.blocks.count, 1)
        XCTAssertEqual(output.conflicts.count, 1)
    }

    func testCriticalManualStartReservesOnlyCompatibleCapacity() throws {
        let critical = explicitTask(title: "Critical", blocks: [block(0, 60)], priority: .critical,
                                    manualStartBy: date(17))
        let normal = explicitTask(title: "Normal", blocks: [block(0, 60)], priority: .normal,
                                  manualStartBy: nil)
        let output = try DeterministicPlanner.generatePlan(tasks: [normal, critical],
            dayCapacities: [capacity(17, [60], kind: .school)],
            lockedBlocks: [], now: date(17), calendar: calendar)
        XCTAssertEqual(output.blocks.map(\.taskID), [critical.id])
        XCTAssertFalse(output.conflicts.isEmpty)
    }

    func testThreeExplicitBlocksRemainThreeLogicalBlocks() {
        let blocks = [block(0, 60), block(1, 90), block(2, 120)]
        XCTAssertEqual(explicitTask(blocks: blocks).blocks.count, 3)
    }

    func testNonSplittable120CreatesExactlyOneSession() throws {
        let output = try plan(explicitTask(blocks: [block(0, 120, splittable: false)]),
                              days: [capacity(17, [120])])
        XCTAssertEqual(output.blocks.map(\.minutes), [120])
    }

    func testSplittable120UsesTwoSixtyMinuteSessionsWhenNecessary() throws {
        let output = try plan(explicitTask(blocks: [block(0, 120, minimum: 45)]),
                              days: [capacity(17, [60]), capacity(18, [60])])
        XCTAssertEqual(output.blocks.map(\.minutes), [60, 60])
        XCTAssertTrue(output.blocks.allSatisfy { $0.mode == .deep })
    }

    func testOne120WindowIsPreferredOverTwoSixtyWindows() throws {
        let output = try plan(explicitTask(blocks: [block(0, 120)]),
                              days: [capacity(17, [60, 60]), capacity(18, [120])])
        XCTAssertEqual(output.blocks.count, 1); XCTAssertEqual(output.blocks[0].minutes, 120)
    }

    func test150SplitsIntoValidSixtyAndNinetyPreservingTotal() throws {
        let output = try plan(explicitTask(blocks: [block(0, 150, minimum: 60)]),
                              days: [capacity(17, [60]), capacity(18, [90])])
        XCTAssertEqual(output.blocks.map(\.minutes).sorted(), [60, 90])
        XCTAssertEqual(output.blocks.reduce(0) { $0 + $1.minutes }, 150)
    }

    func testMinimumSessionRejectsFortyFivePlusOneHundredFive() throws {
        let output = try plan(explicitTask(blocks: [block(0, 150, minimum: 60)]),
                              days: [capacity(17, [45]), capacity(18, [105])])
        XCTAssertTrue(output.blocks.isEmpty); XCTAssertEqual(output.conflicts.first?.reason, .minimumSession)
    }

    func testBlockOrderIsPreserved() throws {
        let first = block(0, 60); let second = block(1, 60)
        let output = try plan(explicitTask(blocks: [first, second]),
                              days: [capacity(17, [60]), capacity(18, [60])])
        let dates = Dictionary(uniqueKeysWithValues: output.blocks.compactMap { block in
            block.blockDefinitionID.map { ($0, block.date) }
        })
        XCTAssertLessThanOrEqual(try XCTUnwrap(dates[first.id]), try XCTUnwrap(dates[second.id]))
    }

    func testLockedSplitSessionKeepsItsModeAndOnlySchedulesRemainingMinutes() throws {
        let logical = block(0, 120, minimum: 45)
        let task = explicitTask(blocks: [logical])
        let locked = PlannerLockedBlock(taskID: task.id, date: date(17), mode: .deep,
                                        period: .deep1, estimatedMinutes: 60,
                                        blockDefinitionID: logical.id)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [task], dayCapacities: [capacity(17, [60]), capacity(18, [60])],
            lockedBlocks: [locked], now: date(17), calendar: calendar
        )
        XCTAssertEqual(output.blocks.count, 1)
        XCTAssertEqual(output.blocks[0].minutes, 60)
        XCTAssertEqual(output.blocks[0].mode, .deep)
        XCTAssertEqual(output.blocks[0].blockDefinitionID, logical.id)
    }

    func testBlockCompletionRequiresAllSessionMinutes() {
        let definition = TaskBlockDefinition(taskID: UUID(), orderIndex: 0, title: "Study", estimatedMinutes: 120)
        let one = WorkBlock(taskID: definition.taskID, date: date(17), period: .deep1, mode: .deep,
                            estimatedMinutes: 60, status: .done, taskBlockDefinitionID: definition.id)
        let two = WorkBlock(taskID: definition.taskID, date: date(18), period: .deep1, mode: .deep,
                            estimatedMinutes: 60, taskBlockDefinitionID: definition.id)
        definition.refreshStatus(sessions: [one, two], taskDefaultMinutes: 60)
        XCTAssertEqual(definition.status, .inProgress)
        two.status = .done; definition.refreshStatus(sessions: [one, two], taskDefaultMinutes: 60)
        XCTAssertEqual(definition.status, .done)
    }

    func testFormatV2ParsesMultipleBlocksAndExplicitStartBy() throws {
        let result = EasyTodoTaskTextParser.parse(v2Task, calendar: calendar)
        let task = try XCTUnwrap(result.tasks.first)
        XCTAssertFalse(result.hasErrors); XCTAssertEqual(task.blocks.count, 2)
        XCTAssertEqual(task.manualStartBy, date(17)); XCTAssertEqual(task.blocks[0].estimatedMinutes, 150)
        XCTAssertEqual(task.blocks[1].minimumSessionMinutes, 45)
    }

    func testFormatV2SupportsAutoStartAndMinutes() throws {
        let text = v2Task.replacingOccurrences(of: "start_by: 2026-09-17", with: "start_by: auto")
            .replacingOccurrences(of: "minutes: 150", with: "minutes: auto")
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(text, calendar: calendar).tasks.first)
        XCTAssertNil(task.manualStartBy); XCTAssertNil(task.blocks[0].estimatedMinutes)
    }

    func testFormatV2MultipleTasksAndMalformedNestedBlock() {
        XCTAssertEqual(EasyTodoTaskTextParser.parse(v2Task + "\n" + v2Task, calendar: calendar).tasks.count, 2)
        let malformed = v2Task.replacingOccurrences(of: "[/BLOCK]", with: "", options: [], range: v2Task.range(of: "[/BLOCK]"))
        XCTAssertTrue(EasyTodoTaskTextParser.parse(malformed, calendar: calendar).hasErrors)
    }

    func testLegacyTaskCreatesGenericDefinitionsAndMapsExistingSessions() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let context = container.mainContext
        let task = TodoTask(title: "Legacy")
        task.estimatedBlocks = 2
        task.completedBlocks = 0
        let firstSession = WorkBlock(taskID: task.id, date: date(17), period: .deep1, mode: .deep,
                                     estimatedMinutes: 60, status: .done)
        let secondSession = WorkBlock(taskID: task.id, date: date(18), period: .deep1, mode: .deep,
                                      estimatedMinutes: 60)
        context.insert(task); context.insert(firstSession); context.insert(secondSession)
        try context.save()

        var definitions = [TaskBlockDefinition]()
        try PlannerCoordinator.ensureTaskBlockDefinitions(for: [task], definitions: &definitions,
                                                           sessions: [firstSession, secondSession], in: context)

        XCTAssertEqual(definitions.map(\.title), ["Block 1", "Block 2"])
        XCTAssertEqual(firstSession.taskBlockDefinitionID, definitions[0].id)
        XCTAssertEqual(secondSession.taskBlockDefinitionID, definitions[1].id)
        XCTAssertEqual(task.completedBlocks, 1)
        XCTAssertFalse(task.isCompleted)
    }

    private func block(_ order: Int, _ minutes: Int, splittable: Bool = true, minimum: Int = 15) -> PlannerBlockInput {
        PlannerBlockInput(id: UUID(), orderIndex: order, title: "Block \(order + 1)", remainingMinutes: minutes,
                          estimatedMinutes: minutes, splittable: splittable, minimumSessionMinutes: minimum)
    }
    private func explicitTask(title: String = "Exam", blocks: [PlannerBlockInput], priority: TaskPriority = .normal,
                              manualStartBy: Date? = nil) -> PlannerTaskInput {
        PlannerTaskInput(id: UUID(), title: title, deadline: date(18), deadlineType: .hard, mode: .deep,
                         size: .large, energy: .high, remainingBlocks: blocks.count, blockMinutes: 60,
                         splittable: true, uncertainty: .low, dependencies: [], meetingDate: nil,
                         priority: priority, manualPriority: nil, manualStartBy: manualStartBy, blocks: blocks)
    }
    private func plan(_ input: PlannerTaskInput, days: [PlannerCapacityDay]) throws -> PlannerOutput {
        try DeterministicPlanner.generatePlan(tasks: [input], dayCapacities: days,
                                              lockedBlocks: [], now: date(17), calendar: calendar)
    }
    private func capacity(_ day: Int, _ minutes: [Int], kind: DayTemplateKind = .free) -> PlannerCapacityDay {
        PlannerCapacityDay(date: date(day), kind: kind, deep: minutes.count, medium: 0, fragment: 0,
                           preferredDeepPeriods: [.deep1, .deep2], deepPeriodMinutes: minutes)
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day))!
    }

    private var v2Task: String {
        """
        [TASK]
        title: AdvMath SA
        project: none
        due: 2026-09-21
        time: none
        deadline: official
        priority: auto
        start_by: 2026-09-17
        work: deep
        size: XL
        energy: high
        uncertainty: medium
        depends_on: none
        related_date: none
        notes: Study

        [BLOCK]
        name: Relearn concepts
        minutes: 150
        splittable: yes
        min_session_minutes: 60
        [/BLOCK]

        [BLOCK]
        name: Practice
        minutes: 120
        splittable: yes
        min_session_minutes: 45
        [/BLOCK]
        [/TASK]
        """
    }
}
