import SwiftData
import XCTest
@testable import EasyTODO

@MainActor
final class TaskImportTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return value
    }

    func testSingleValidTaskParsing() throws {
        let result = EasyTodoTaskTextParser.parse(taskBlock(title: "Write draft"), calendar: calendar)
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.tasks.first?.title, "Write draft")
        XCTAssertFalse(result.hasErrors)
    }

    func testMultipleTaskBlocksParseFromRegressionFixture() {
        let result = EasyTodoTaskTextParser.parse(Self.sampleBatch, calendar: calendar)
        XCTAssertEqual(result.tasks.map(\.title), ["AdvMath SA", "Research Agenda 3"])
        XCTAssertFalse(result.hasErrors)
    }

    func testDateUsesStrictYearMonthDayFormat() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(), calendar: calendar).tasks.first)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(task.dueDate)),
                       DateComponents(year: 2026, month: 9, day: 21))
    }

    func testExplicitTimeSetsHasExplicitDueTime() throws {
        let parsed = EasyTodoTaskTextParser.parse(taskBlock(time: "14:35"), calendar: calendar)
        let task = try XCTUnwrap(parsed.tasks.first)
        XCTAssertTrue(task.hasExplicitDueTime)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(task.dueDate)), 14)
        XCTAssertEqual(calendar.component(.minute, from: try XCTUnwrap(task.dueDate)), 35)
    }

    func testTimeNoneProducesDateOnlyDeadline() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(time: "none"), calendar: calendar).tasks.first)
        XCTAssertFalse(task.hasExplicitDueTime)
        XCTAssertEqual(task.dueDate, task.dueDate.map(calendar.startOfDay(for:)))
    }

    func testOfficialMapsToHardAndUserSelected() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(deadline: "official"), calendar: calendar).tasks.first)
        XCTAssertEqual(task.deadlineType, .hard)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testMyDeadlineMapsToInternalAndUserSelected() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(deadline: "my"), calendar: calendar).tasks.first)
        XCTAssertEqual(task.deadlineType, .internalDeadline)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testConfirmLeavesDeadlineUnconfirmed() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(deadline: "confirm"), calendar: calendar).tasks.first)
        XCTAssertNil(task.deadlineType)
        XCTAssertNil(task.deadlineTypeSource)
    }

    func testWorkModeMappings() throws {
        XCTAssertEqual(try parsed(work: "deep").workMode, .deep)
        XCTAssertEqual(try parsed(work: "medium").workMode, .medium)
        XCTAssertEqual(try parsed(work: "fragmentable").workMode, .fragmentable)
    }

    func testSizeMappings() throws {
        XCTAssertEqual(try parsed(size: "S").size, .small)
        XCTAssertEqual(try parsed(size: "M").size, .medium)
        XCTAssertEqual(try parsed(size: "L").size, .large)
        XCTAssertEqual(try parsed(size: "XL").size, .extraLarge)
    }

    func testExplicitBlocksPersistCorrectly() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let result = EasyTodoTaskTextParser.parse(taskBlock(blocks: "4"), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        _ = try TaskImportCoordinator.importTasks(preview, in: container.mainContext, now: now, calendar: calendar)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TodoTask>()).first?.estimatedBlocks, 4)
        let definitions = try container.mainContext.fetch(FetchDescriptor<TaskBlockDefinition>())
        XCTAssertEqual(definitions.count, 4)
        XCTAssertEqual(definitions.map(\.title).sorted(), ["Block 1", "Block 2", "Block 3", "Block 4"])
    }

    func testAutoMinuteFieldsRemainNil() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(), calendar: calendar).tasks.first)
        XCTAssertNil(task.blockMinutes)
        XCTAssertNil(task.minimumBlockMinutes)
    }

    func testSplittableYesNoParsing() throws {
        XCTAssertEqual(try parsed(splittable: "yes").splittable, true)
        XCTAssertEqual(try parsed(splittable: "no").splittable, false)
    }

    func testSemicolonDependenciesAreParsed() throws {
        let task = try XCTUnwrap(EasyTodoTaskTextParser.parse(
            taskBlock(dependsOn: "Research Agenda 3; Method supplementary research"), calendar: calendar
        ).tasks.first)
        XCTAssertEqual(task.dependencyTitles, ["Research Agenda 3", "Method supplementary research"])
    }

    func testDependencyResolvesWithinSameBatchBeforeExistingTasks() throws {
        let first = taskBlock(title: "Research Agenda 3")
        let second = taskBlock(title: "Draft", dependsOn: "Research Agenda 3")
        let result = EasyTodoTaskTextParser.parse(first + "\n" + second, calendar: calendar)
        let existing = TodoTask(title: "Research Agenda 3")
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [existing], categories: [], calendar: calendar)
        XCTAssertEqual(preview[1].dependencyIDs, [preview[0].id])
    }

    func testUnresolvedDependencyProducesWarning() {
        let result = EasyTodoTaskTextParser.parse(taskBlock(dependsOn: "Missing task"), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        XCTAssertTrue(preview[0].issues.contains { $0.kind == .unresolvedDependency && $0.severity == .warning })
        XCTAssertTrue(preview[0].dependencyIDs.isEmpty)
    }

    func testMalformedDateIsAnError() {
        let result = EasyTodoTaskTextParser.parse(taskBlock(due: "09/21/2026"), calendar: calendar)
        XCTAssertTrue(result.issues.contains { $0.severity == .error && $0.message.contains("YYYY-MM-DD") })
    }

    func testMalformedIntegerIsAnError() {
        let result = EasyTodoTaskTextParser.parse(taskBlock(blocks: "many"), calendar: calendar)
        XCTAssertTrue(result.issues.contains { $0.severity == .error && $0.message.contains("positive integer") })
    }

    func testUnknownFieldIsAnError() {
        let text = taskBlock().replacingOccurrences(of: "blocks: 3", with: "blokcs: 3")
        let result = EasyTodoTaskTextParser.parse(text, calendar: calendar)
        XCTAssertTrue(result.issues.contains { $0.kind == .invalidField && $0.message.contains("blokcs") })
    }

    func testMissingTitleIsAnError() {
        let result = EasyTodoTaskTextParser.parse(taskBlock(title: ""), calendar: calendar)
        XCTAssertTrue(result.issues.contains { $0.kind == .missingTitle && $0.severity == .error })
    }

    func testPossibleDuplicateWarnsAndDefaultsToSkipped() throws {
        let existing = TodoTask(title: "  AdvMath   SA ", scheduledDate: try dueDate())
        let result = EasyTodoTaskTextParser.parse(taskBlock(), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [existing], categories: [], calendar: calendar)
        XCTAssertTrue(preview[0].issues.contains { $0.kind == .possibleDuplicate })
        XCTAssertFalse(preview[0].isIncluded)
    }

    func testUnknownProjectWarns() {
        let result = EasyTodoTaskTextParser.parse(taskBlock(project: "School"), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        XCTAssertTrue(preview[0].issues.contains { $0.kind == .unknownProject })
    }

    func testStructuredDeadlineOverridesAssessmentAutoDetection() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let result = EasyTodoTaskTextParser.parse(taskBlock(deadline: "my"), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        _ = try TaskImportCoordinator.importTasks(preview, in: container.mainContext, now: now, calendar: calendar)
        let task = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        XCTAssertEqual(task.deadlineType, .internalDeadline)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testEstimateConfirmationStoresExplicitMetadataAndClearsWarning() {
        let task = TodoTask(title: "Legacy")
        XCTAssertTrue(task.needsPlannerMetadata)
        task.setPlanningEstimate(workMode: .deep, size: .extraLarge, estimatedBlocks: 3,
                                 energy: .high, uncertainty: .medium, splittable: true)
        XCTAssertFalse(task.needsPlannerMetadata)
        XCTAssertEqual(task.workModeRawValue, WorkMode.deep.rawValue)
        XCTAssertEqual(task.estimatedBlocks, 3)
    }

    func testSelectingOfficialSetsUserSelectedSource() {
        let task = TodoTask(title: "Deadline", scheduledDate: .now)
        task.userSelectDeadlineType(.hard)
        XCTAssertEqual(task.deadlineType, .hard)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testSelectingMyDeadlineSetsUserSelectedSource() {
        let task = TodoTask(title: "Deadline", scheduledDate: .now)
        task.userSelectDeadlineType(.internalDeadline)
        XCTAssertEqual(task.deadlineType, .internalDeadline)
        XCTAssertEqual(task.deadlineTypeSource, .userSelected)
    }

    func testDeadlineSourceDescriptionIsDerivedFromClassification() {
        let task = TodoTask(title: "AdvMath SA", scheduledDate: .now)
        XCTAssertEqual(task.deadlineSourceDescription, "Legacy / needs confirmation")
        task.setDeadlineType(.hard, source: .autoDetected)
        XCTAssertEqual(task.deadlineSourceDescription, "Auto-detected from “SA”")
        task.userSelectDeadlineType(.internalDeadline)
        XCTAssertEqual(task.deadlineSourceDescription, "User selected")
    }

    func testImportedTasksTriggerNormalReplan() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let result = EasyTodoTaskTextParser.parse(taskBlock(), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 17)))
        let imported = try TaskImportCoordinator.importTasks(preview, in: container.mainContext,
                                                              now: now, calendar: calendar)
        let task = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        XCTAssertEqual(imported.importedCount, 1)
        XCTAssertNotNil(task.executionRank)
        XCTAssertFalse(imported.plan.output.blocks.isEmpty)
    }

    func testExplicitNormalPriorityForAssessmentWins() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let result = EasyTodoTaskTextParser.parse(taskBlock(priority: "normal"), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        _ = try TaskImportCoordinator.importTasks(preview, in: container.mainContext,
                                                   now: date(2026, 9, 17), calendar: calendar)
        let task = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        XCTAssertEqual(task.priority, .normal)
        XCTAssertEqual(task.prioritySource, .userSelected)
    }

    func testAutoPriorityForAssessmentBecomesCritical() throws {
        let container = try PersistenceController.modelContainer(inMemory: true)
        let result = EasyTodoTaskTextParser.parse(taskBlock(priority: "auto"), calendar: calendar)
        let preview = TaskImportCoordinator.preview(parseResult: result, existingTasks: [], categories: [], calendar: calendar)
        _ = try TaskImportCoordinator.importTasks(preview, in: container.mainContext,
                                                   now: date(2026, 9, 17), calendar: calendar)
        let task = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<TodoTask>()).first)
        XCTAssertEqual(task.priority, .critical)
        XCTAssertEqual(task.prioritySource, .autoDetected)
    }

    func testLegacyTaskFormatWithoutPriorityStillImports() throws {
        let result = EasyTodoTaskTextParser.parse(taskBlock(priority: nil), calendar: calendar)
        XCTAssertFalse(result.hasErrors)
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertNil(result.tasks[0].priority)
    }

    private func parsed(work: String = "deep", size: String = "XL",
                        splittable: String = "yes") throws -> ParsedTaskDTO {
        try XCTUnwrap(EasyTodoTaskTextParser.parse(taskBlock(work: work, size: size,
                                                             splittable: splittable),
                                                   calendar: calendar).tasks.first)
    }

    private func dueDate() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func taskBlock(title: String = "AdvMath SA", project: String = "none",
                           due: String = "2026-09-21", time: String = "none",
                           deadline: String = "official", priority: String? = nil, work: String = "deep",
                           size: String = "XL", blocks: String = "3",
                           splittable: String = "yes", dependsOn: String = "none") -> String {
        """
        [TASK]
        title: \(title)
        project: \(project)
        due: \(due)
        time: \(time)
        deadline: \(deadline)
        \(priority.map { "priority: \($0)" } ?? "")
        work: \(work)
        size: \(size)
        blocks: \(blocks)
        block_minutes: auto
        energy: high
        uncertainty: medium
        splittable: \(splittable)
        min_block_minutes: auto
        depends_on: \(dependsOn)
        related_date: none
        notes: Test import
        [/TASK]
        """
    }

    private static let sampleBatch = """
    [TASK]
    title: AdvMath SA
    project: School
    due: 2026-09-21
    time: none
    deadline: official
    work: deep
    size: XL
    blocks: 3
    block_minutes: auto
    energy: high
    uncertainty: medium
    splittable: yes
    min_block_minutes: 60
    depends_on: none
    related_date: none
    notes: Summative assessment. Most content needs to be relearned before practice.
    [/TASK]

    [TASK]
    title: Research Agenda 3
    project: Research
    due: 2026-09-18
    time: none
    deadline: my
    work: deep
    size: XL
    blocks: 2
    block_minutes: auto
    energy: high
    uncertainty: high
    splittable: yes
    min_block_minutes: 60
    depends_on: none
    related_date: 2026-09-23
    notes: Reread literature and reconsider methodology, target population, and variables.
    [/TASK]
    """
}
