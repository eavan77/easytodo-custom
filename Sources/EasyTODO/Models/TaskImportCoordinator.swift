import Foundation
import SwiftData

enum ImportProjectChoice: Equatable, Hashable {
    case none
    case existing(UUID)
    case create(String)
}

struct TaskImportPreviewItem: Identifiable, Equatable {
    var dto: ParsedTaskDTO
    var isIncluded: Bool
    var projectChoice: ImportProjectChoice
    var dependencyIDs: [UUID]
    var issues: [ImportValidationIssue]
    var id: UUID { dto.id }
    var hasErrors: Bool { issues.contains { $0.severity == .error } }
    var isPossibleDuplicate: Bool { issues.contains { $0.kind == .possibleDuplicate } }
}

struct TaskImportResult {
    let importedCount: Int
    let plan: AppliedPlan
}

enum TaskImportCoordinator {
    static func preview(parseResult: TaskTextParseResult, existingTasks: [TodoTask],
                        categories: [TaskCategory], calendar: Calendar = .current) -> [TaskImportPreviewItem] {
        let active = existingTasks.filter { !$0.isCompleted }
        return parseResult.tasks.enumerated().map { index, dto in
            var issues = parseResult.issues.filter { $0.taskIndex == index }
            let projectChoice: ImportProjectChoice
            if let projectName = dto.projectName {
                let matches = categories.filter { $0.name.caseInsensitiveCompare(projectName) == .orderedSame }
                if matches.count == 1 {
                    projectChoice = .existing(matches[0].id)
                } else {
                    projectChoice = .none
                    issues.append(ImportValidationIssue(
                        severity: .warning, kind: .unknownProject, taskIndex: index, line: nil,
                        message: "Unknown project: “\(projectName)”. Choose a project, create it, or import without one."
                    ))
                }
            } else { projectChoice = .none }

            var dependencyIDs: [UUID] = []
            for title in dto.dependencyTitles {
                let batchMatches = parseResult.tasks.filter { $0.title == title && $0.id != dto.id }
                if batchMatches.count == 1 {
                    dependencyIDs.append(batchMatches[0].id)
                    continue
                }
                if batchMatches.count > 1 {
                    issues.append(dependencyIssue(.ambiguousDependency, index,
                                                  "Dependency “\(title)” is ambiguous in this import."))
                    continue
                }
                let existingMatches = active.filter { $0.title == title }
                if existingMatches.count == 1 {
                    dependencyIDs.append(existingMatches[0].id)
                } else if existingMatches.count > 1 {
                    issues.append(dependencyIssue(.ambiguousDependency, index,
                                                  "Dependency “\(title)” matches multiple existing tasks."))
                } else {
                    issues.append(dependencyIssue(.unresolvedDependency, index,
                                                  "Dependency “\(title)” was not found and will be omitted."))
                }
            }

            if active.contains(where: { isDuplicate(dto, $0, calendar: calendar) }) {
                issues.append(ImportValidationIssue(
                    severity: .warning, kind: .possibleDuplicate, taskIndex: index, line: nil,
                    message: "Possible duplicate: an active task has the same title and due date."
                ))
            }
            if dto.deadlineType == .internalDeadline,
               let match = FixedAssessmentRecognizer.match(in: dto.title) {
                issues.append(ImportValidationIssue(
                    severity: .warning, kind: .assessmentDeadlineMismatch, taskIndex: index, line: nil,
                    message: "Title looks like a fixed assessment (“\(match.phrase)”), but deadline is marked My deadline."
                ))
            }
            return TaskImportPreviewItem(dto: dto,
                                         isIncluded: !issues.contains { $0.kind == .possibleDuplicate },
                                         projectChoice: projectChoice, dependencyIDs: dependencyIDs,
                                         issues: issues)
        }
    }

    @MainActor
    static func importTasks(_ items: [TaskImportPreviewItem], in context: ModelContext,
                            now: Date = .now, calendar: Calendar = .current) throws -> TaskImportResult {
        let selected = items.filter { $0.isIncluded && !$0.hasErrors }
        guard !selected.isEmpty else { throw TaskImportError.noImportableTasks }
        let existingTasks = try context.fetch(FetchDescriptor<TodoTask>())
        var categories = try context.fetch(FetchDescriptor<TaskCategory>())
        var createdByName: [String: TaskCategory] = [:]
        var nextCategoryOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        var nextSortByDay: [String: Int] = [:]
        let validDependencyIDs = Set(existingTasks.map(\.id)).union(selected.map(\.dto.id))

        for item in selected {
            let dto = item.dto
            let dayKey = dto.dueDate.map { String(Int(calendar.startOfDay(for: $0).timeIntervalSince1970)) } ?? "none"
            let existingMax = existingTasks.filter {
                switch ($0.scheduledDate, dto.dueDate) {
                case (nil, nil): true
                case let (left?, right?): calendar.isDate(left, inSameDayAs: right)
                default: false
                }
            }.map(\.sortOrder).max() ?? -1
            let sortOrder = nextSortByDay[dayKey] ?? (existingMax + 1)
            nextSortByDay[dayKey] = sortOrder + 1

            let task = TodoTask(title: dto.title, sortOrder: sortOrder, scheduledDate: dto.dueDate,
                                hasExplicitDueTime: dto.hasExplicitDueTime)
            task.id = dto.id
            task.notes = dto.notes.isEmpty ? nil : dto.notes
            task.relatedMeetingDate = dto.relatedDate
            task.manualStartBy = dto.manualStartBy
            task.dependencyIDs = item.dependencyIDs.filter(validDependencyIDs.contains)
            if let type = dto.deadlineType {
                task.setDeadlineType(type, source: dto.deadlineTypeSource ?? .userSelected)
            } else {
                task.deadlineTypeRawValue = nil
                task.deadlineTypeSourceRawValue = nil
            }
            if let priority = dto.priority {
                task.priority = priority
                task.prioritySource = dto.prioritySource ?? .userSelected
            } else {
                task.planningPriorityRawValue = nil
                task.prioritySourceRawValue = nil
            }
            if let mode = dto.workMode { task.workMode = mode }
            if let size = dto.size { task.taskSize = size }
            task.estimatedBlocks = dto.blocks.isEmpty ? dto.estimatedBlocks : dto.blocks.count
            if !dto.blocks.isEmpty, dto.blocks.allSatisfy({ $0.estimatedMinutes != nil }) {
                task.estimatedMinutes = dto.blocks.compactMap(\.estimatedMinutes).reduce(0, +)
            } else if let blockMinutes = dto.blockMinutes {
                task.estimatedMinutes = blockMinutes * max(1, dto.estimatedBlocks ?? task.safeEstimatedBlocks)
            }
            if let energy = dto.energy { task.energyDemand = energy }
            if let uncertainty = dto.uncertainty { task.uncertainty = uncertainty }
            task.splittable = dto.splittable
            task.minimumBlockMinutes = dto.minimumBlockMinutes

            switch item.projectChoice {
            case .none:
                break
            case let .existing(id):
                task.category = categories.first { $0.id == id }
            case let .create(name):
                let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if let category = createdByName[key] ?? categories.first(where: {
                    $0.name.caseInsensitiveCompare(name) == .orderedSame
                }) {
                    task.category = category
                } else {
                    let category = TaskCategory(name: name, sortOrder: nextCategoryOrder)
                    nextCategoryOrder += 1
                    context.insert(category)
                    categories.append(category)
                    createdByName[key] = category
                    task.category = category
                }
            }
            context.insert(task)
            for (index, block) in dto.blocks.enumerated() {
                context.insert(TaskBlockDefinition(id: block.id, taskID: task.id, orderIndex: index,
                                                   title: block.name, estimatedMinutes: block.estimatedMinutes,
                                                   splittable: block.splittable,
                                                   minimumSessionMinutes: block.minimumSessionMinutes))
            }
        }
        do {
            let plan = try PlannerCoordinator.replan(in: context, now: now, calendar: calendar)
            return TaskImportResult(importedCount: selected.count, plan: plan)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func dependencyIssue(_ kind: ImportIssueKind, _ taskIndex: Int,
                                        _ message: String) -> ImportValidationIssue {
        ImportValidationIssue(severity: .warning, kind: kind, taskIndex: taskIndex,
                              line: nil, message: message)
    }

    private static func isDuplicate(_ dto: ParsedTaskDTO, _ task: TodoTask, calendar: Calendar) -> Bool {
        guard normalized(dto.title) == normalized(task.title) else { return false }
        switch (dto.dueDate, task.scheduledDate) {
        case (nil, nil): return true
        case let (left?, right?): return calendar.isDate(left, inSameDayAs: right)
        default: return false
        }
    }

    private static func normalized(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

enum TaskImportError: LocalizedError {
    case noImportableTasks
    var errorDescription: String? { "No importable tasks are selected." }
}
