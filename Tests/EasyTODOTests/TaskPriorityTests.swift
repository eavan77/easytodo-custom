import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class TaskPriorityTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return value
    }

    func testAssessmentDefaultsToCriticalAutoDetected() throws {
        let value = try recognizedPriority(title: "AdvMath SA")
        XCTAssertEqual(value.priority, .critical)
        XCTAssertEqual(value.source, .autoDetected)
        XCTAssertEqual(value.description, "Auto-detected from “SA”")
    }

    func testExamDefaultsToCriticalAutoDetected() throws {
        let value = try recognizedPriority(title: "Math Exam")
        XCTAssertEqual(value.priority, .critical)
        XCTAssertEqual(value.source, .autoDetected)
    }

    func testOrdinaryTaskDefaultsToNormal() throws {
        let value = try recognizedPriority(title: "CommonApp CV")
        XCTAssertEqual(value.priority, .normal)
        XCTAssertEqual(value.source, .default)
    }

    func testManualPriorityOverrideSurvivesAssessmentRecognition() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let task = TodoTask(title: "AdvMath SA")
        task.userSelectPriority(.normal)
        container.mainContext.insert(task)
        try PlannerCoordinator.applyAutomaticPriorityRecognition([task], in: container.mainContext)
        XCTAssertEqual(task.priority, .normal)
        XCTAssertEqual(task.prioritySource, .userSelected)
    }

    func testCriticalDeepTaskReceivesOnlyCompatibleSlotBeforeNormal() throws {
        let day = date(2026, 9, 17)
        let critical = input("Exam", deadline: day, mode: .deep, blocks: 1, priority: .critical)
        let normal = input("Draft", deadline: day, mode: .deep, blocks: 1, priority: .normal)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [normal, critical], dayCapacities: [capacity(day, deep: 1)],
            lockedBlocks: [], now: day, calendar: calendar
        )
        XCTAssertEqual(output.blocks.map(\.taskID), [critical.id])
        XCTAssertEqual(ConflictResolver.shortfall(in: output), 1)
    }

    func testLowerPriorityUsesGenuinelyLeftoverCompatibleCapacity() throws {
        let day = date(2026, 9, 17)
        let critical = input("Exam", deadline: day, mode: .deep, blocks: 1, priority: .critical)
        let normal = input("Draft", deadline: day, mode: .deep, blocks: 1, priority: .normal)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [normal, critical], dayCapacities: [capacity(day, deep: 2)],
            lockedBlocks: [], now: day, calendar: calendar
        )
        XCTAssertEqual(Set(output.blocks.map(\.taskID)), Set([critical.id, normal.id]))
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    func testCriticalRanksAheadOfEarlierNormalInternalDeadline() throws {
        let today = date(2026, 9, 17)
        let normal = input("CV", deadline: today, deadlineType: .internalDeadline,
                           mode: .deep, blocks: 1, priority: .normal)
        let critical = input("Exam", deadline: date(2026, 9, 19), mode: .deep,
                             blocks: 1, priority: .critical)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [normal, critical], dayCapacities: [capacity(today, deep: 2),
                capacity(date(2026, 9, 18), deep: 2), capacity(date(2026, 9, 19), deep: 2)],
            lockedBlocks: [], now: today, calendar: calendar
        )
        XCTAssertEqual(output.taskMetadata[critical.id]?.executionRank, 1)
        XCTAssertEqual(output.taskMetadata[normal.id]?.executionRank, 2)
    }

    func testHardDeadlineCollisionSurfacesConflictWithoutSacrificingCritical() throws {
        let day = date(2026, 9, 17)
        let critical = input("Exam", deadline: day, mode: .deep, blocks: 2, priority: .critical)
        let normal = input("Submission", deadline: day, mode: .deep, blocks: 2, priority: .normal)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [normal, critical], dayCapacities: [capacity(day, deep: 3)],
            lockedBlocks: [], now: day, calendar: calendar
        )
        XCTAssertEqual(output.blocks.filter { $0.taskID == critical.id }.count, 2)
        XCTAssertEqual(output.blocks.filter { $0.taskID == normal.id }.count, 1)
        XCTAssertEqual(ConflictResolver.shortfall(in: output), 1)
    }

    func testNormalFragmentWorkUsesIndependentCapacityAlongsideCriticalDeepWork() throws {
        let day = date(2026, 9, 17)
        let critical = input("Exam", deadline: day, mode: .deep, blocks: 1, priority: .critical)
        let normal = input("Email", deadline: day, mode: .fragmentable, blocks: 1, priority: .normal,
                           minutes: 30)
        let output = try DeterministicPlanner.generatePlan(
            tasks: [normal, critical], dayCapacities: [capacity(day, deep: 1, fragment: 1)],
            lockedBlocks: [], now: day, calendar: calendar
        )
        XCTAssertEqual(Set(output.blocks.map(\.taskID)), Set([critical.id, normal.id]))
        XCTAssertTrue(output.conflicts.isEmpty)
    }

    private func recognizedPriority(title: String) throws -> (priority: TaskPriority, source: PrioritySource, description: String) {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let task = TodoTask(title: title)
        container.mainContext.insert(task)
        try PlannerCoordinator.applyAutomaticPriorityRecognition([task], in: container.mainContext)
        return (task.priority, task.prioritySource, task.prioritySourceDescription)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func input(_ title: String, deadline: Date, deadlineType: DeadlineType = .hard,
                       mode: WorkMode, blocks: Int, priority: TaskPriority, minutes: Int = 60) -> PlannerTaskInput {
        PlannerTaskInput(id: UUID(), title: title, deadline: deadline, deadlineType: deadlineType,
                         mode: mode, size: .medium, energy: .medium, remainingBlocks: blocks,
                         blockMinutes: minutes, splittable: true, uncertainty: .low,
                         dependencies: [], meetingDate: nil, priority: priority, manualPriority: nil)
    }

    private func capacity(_ date: Date, deep: Int, fragment: Int = 0) -> PlannerCapacityDay {
        PlannerCapacityDay(date: date, kind: .free, deep: deep, medium: 0, fragment: fragment,
                           preferredDeepPeriods: [.deep1, .deep2])
    }
}
