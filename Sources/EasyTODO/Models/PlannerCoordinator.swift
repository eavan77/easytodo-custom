import Foundation
import SwiftData

struct WorkBlockSnapshot: Equatable {
    let id: UUID
    let taskID: UUID
    let date: Date
    let period: WorkBlockPeriod
    let mode: WorkMode
    let estimatedMinutes: Int
    let status: WorkBlockStatus
    let locked: Bool
    let actualMinutes: Int?
    let notes: String
    let splitGroupID: UUID?
    let taskBlockDefinitionID: UUID?
    let sessionOrderIndex: Int?
}

struct TaskPlanSnapshot: Equatable {
    let taskID: UUID
    let startBy: Date?
    let plannedStart: Date?
    let executionRank: Int?
    let plannerReason: String?
    let scheduledDate: Date?
    let hasExplicitDueTime: Bool
    let deadlineTypeRawValue: String?
    let deadlineTypeSourceRawValue: String?
    let planningPriorityRawValue: String?
    let prioritySourceRawValue: String?
    let estimatedBlocks: Int?
    let manualStartBy: Date?
}

struct CapacityOverrideSnapshot: Equatable {
    let id: UUID
    let date: Date
    let additionalDeepCapacity: Int
    let additionalMediumCapacity: Int
    let additionalFragmentCapacity: Int
    let reason: String
    let createdAt: Date
}

struct PlannerUndoSnapshot: Equatable {
    let blocks: [WorkBlockSnapshot]
    let tasks: [TaskPlanSnapshot]
    let capacityOverrides: [CapacityOverrideSnapshot]
    let acknowledgedConflictKeys: [String]
}

struct AppliedPlan {
    let output: PlannerOutput
    let undoSnapshot: PlannerUndoSnapshot
    let summary: [String]
}

enum PlannerCoordinator {
    @MainActor
    static func ensureDefaultCapacity(in context: ModelContext) throws -> [DayCapacityTemplate] {
        let existing = try context.fetch(FetchDescriptor<DayCapacityTemplate>())
        guard existing.isEmpty else { return existing }
        let defaults = DefaultCapacityProfile.templates()
        defaults.forEach(context.insert)
        try context.save()
        return defaults
    }

    @MainActor
    static func replan(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> AppliedPlan {
        let allTasks = try context.fetch(FetchDescriptor<TodoTask>())
        try normalizeTaskIdentifiers(allTasks, in: context)
        try applyAutomaticDeadlineRecognition(allTasks, in: context)
        try applyAutomaticPriorityRecognition(allTasks, in: context)
        let existingBlocks = try context.fetch(FetchDescriptor<WorkBlock>())
        var definitions = try context.fetch(FetchDescriptor<TaskBlockDefinition>())
        try ensureTaskBlockDefinitions(for: allTasks, definitions: &definitions,
                                       sessions: existingBlocks, in: context)
        let tasks = allTasks.filter { !$0.isCompleted }
        let templates = try ensureDefaultCapacity(in: context)
        let overrides = try context.fetch(FetchDescriptor<DayCapacityOverride>())
        let acknowledgements = try context.fetch(FetchDescriptor<ScheduleConflictAcknowledgement>())
        let snapshot = PlannerUndoSnapshot(
            blocks: existingBlocks.map(snapshot),
            tasks: tasks.map { TaskPlanSnapshot(taskID: $0.id, startBy: $0.startBy, plannedStart: $0.plannedStart,
                                                executionRank: $0.executionRank, plannerReason: $0.plannerReason,
                                                scheduledDate: $0.scheduledDate,
                                                hasExplicitDueTime: $0.hasExplicitDueTime,
                                                deadlineTypeRawValue: $0.deadlineTypeRawValue,
                                                deadlineTypeSourceRawValue: $0.deadlineTypeSourceRawValue,
                                                planningPriorityRawValue: $0.planningPriorityRawValue,
                                                prioritySourceRawValue: $0.prioritySourceRawValue,
                                                estimatedBlocks: $0.estimatedBlocks,
                                                manualStartBy: $0.manualStartBy) },
            capacityOverrides: overrides.map(snapshot),
            acknowledgedConflictKeys: acknowledgements.map(\.conflictKey)
        )
        let horizon = planningHorizon(tasks: tasks, now: now, calendar: calendar)
        let days = capacityDays(from: templates, overrides: overrides, through: horizon, now: now, calendar: calendar)
        let input = tasks.map { task in
            let taskDefinitions = definitions.filter { $0.taskID == task.id }.sorted { $0.orderIndex < $1.orderIndex }
            let taskSessions = existingBlocks.filter { $0.taskID == task.id }
            let plannerBlocks = taskDefinitions.compactMap { definition -> PlannerBlockInput? in
                let completedMinutes = taskSessions.filter {
                    $0.taskBlockDefinitionID == definition.id && $0.status == .done
                }.reduce(0) { $0 + $1.estimatedMinutes }
                let total = definition.effectiveMinutes(taskDefault: task.plannedBlockMinutes)
                let remaining = max(0, total - completedMinutes)
                guard remaining > 0, definition.status != .done else { return nil }
                return PlannerBlockInput(id: definition.id, orderIndex: definition.orderIndex,
                                         title: definition.title, remainingMinutes: remaining,
                                         estimatedMinutes: definition.estimatedMinutes,
                                         splittable: definition.splittable,
                                         minimumSessionMinutes: max(1, definition.minimumSessionMinutes ?? min(15, total)))
            }
            return PlannerTaskInput(id: task.id, title: task.title, deadline: task.scheduledDate,
                             deadlineType: task.deadlineType, mode: task.workMode, size: task.taskSize,
                             energy: task.energyDemand, remainingBlocks: task.remainingBlocks,
                             blockMinutes: task.plannedBlockMinutes,
                             splittable: task.splittable ?? true,
                             uncertainty: task.uncertainty, dependencies: task.dependencyIDs,
                             meetingDate: task.relatedMeetingDate, priority: task.priority,
                             manualPriority: task.manualPriority, manualStartBy: task.manualStartBy,
                             recommendedStartBy: task.startBy,
                             blocks: plannerBlocks)
        }
        let plannerLockedTaskIDs = Set(tasks.filter(\.isPlannerLocked).map(\.id))
        let locked = existingBlocks.filter { ($0.locked || plannerLockedTaskIDs.contains($0.taskID)) && $0.status != .done }.map {
            PlannerLockedBlock(taskID: $0.taskID, date: calendar.startOfDay(for: $0.date), mode: $0.mode,
                               period: $0.period, estimatedMinutes: $0.estimatedMinutes,
                               blockDefinitionID: $0.taskBlockDefinitionID)
        }
        let output = try DeterministicPlanner.generatePlan(tasks: input, dayCapacities: days,
                                                           lockedBlocks: locked, now: now, calendar: calendar)

        let currentConflictKeys = Set(output.conflicts.map(\.conflictKey))
        for acknowledgement in acknowledgements where !currentConflictKeys.contains(acknowledgement.conflictKey) {
            context.delete(acknowledgement)
        }

        for block in existingBlocks where !block.locked && block.status != .done { context.delete(block) }
        for proposed in output.blocks {
            context.insert(WorkBlock(taskID: proposed.taskID, date: proposed.date, period: proposed.period,
                                     mode: proposed.mode, estimatedMinutes: proposed.minutes,
                                     taskBlockDefinitionID: proposed.blockDefinitionID,
                                     sessionOrderIndex: proposed.sessionOrderIndex))
        }
        for task in tasks {
            guard let metadata = output.taskMetadata[task.id] else { continue }
            task.startBy = metadata.startBy
            task.plannedStart = metadata.plannedStart
            task.executionRank = metadata.executionRank
            task.plannerReason = metadata.reason
            task.blockedBy = task.dependencyIDs.filter { id in tasks.contains { $0.id == id && !$0.isCompleted } }
        }
        try context.save()

        let summary = planSummary(oldBlocks: snapshot.blocks, newBlocks: output.blocks, tasks: tasks, calendar: calendar)
        return AppliedPlan(output: output, undoSnapshot: snapshot, summary: summary)
    }

    @MainActor
    static func applyAutomaticDeadlineRecognition(_ tasks: [TodoTask], in context: ModelContext) throws {
        var changed = false
        for task in tasks where task.deadlineTypeRawValue != nil && task.deadlineTypeSourceRawValue == nil {
            task.deadlineTypeSource = .userSelected
            changed = true
        }
        for task in tasks where task.scheduledDate != nil && task.deadlineTypeSource != .userSelected {
            guard let match = FixedAssessmentRecognizer.match(in: task.title) else { continue }
            if task.deadlineType != .hard || task.deadlineTypeSource != .autoDetected {
                task.setDeadlineType(.hard, source: .autoDetected)
                task.plannerReason = "Fixed assessment detected from “\(match.phrase)”."
                changed = true
            }
        }
        if changed { try context.save() }
    }

    @MainActor
    static func applyAutomaticPriorityRecognition(_ tasks: [TodoTask], in context: ModelContext) throws {
        var changed = false
        for task in tasks where task.prioritySource != .userSelected {
            if FixedAssessmentRecognizer.match(in: task.title) != nil {
                if task.priority != .critical || task.prioritySource != .autoDetected {
                    task.priority = .critical
                    task.prioritySource = .autoDetected
                    changed = true
                }
            } else if task.priority != .normal || task.prioritySource != .default
                        || task.planningPriorityRawValue == nil || task.prioritySourceRawValue == nil {
                task.priority = .normal
                task.prioritySource = .default
                changed = true
            }
        }
        if changed { try context.save() }
    }

    @MainActor
    static func ensureTaskBlockDefinitions(for tasks: [TodoTask], definitions: inout [TaskBlockDefinition],
                                           sessions: [WorkBlock], in context: ModelContext) throws {
        var changed = false
        for task in tasks {
            var taskDefinitions = definitions.filter { $0.taskID == task.id }.sorted { $0.orderIndex < $1.orderIndex }
            if taskDefinitions.isEmpty {
                let count = task.safeEstimatedBlocks
                taskDefinitions = (0..<count).map { index in
                    TaskBlockDefinition(taskID: task.id, orderIndex: index, title: "Block \(index + 1)",
                                        estimatedMinutes: nil, splittable: task.splittable ?? true,
                                        minimumSessionMinutes: task.minimumBlockMinutes,
                                        status: index < task.safeCompletedBlocks ? .done : .planned)
                }
                taskDefinitions.forEach { context.insert($0); definitions.append($0) }
                let unmapped = sessions.filter { $0.taskID == task.id && $0.taskBlockDefinitionID == nil }
                    .sorted(by: sessionOrder)
                for (index, session) in unmapped.enumerated() where !taskDefinitions.isEmpty {
                    session.taskBlockDefinitionID = taskDefinitions[min(index, taskDefinitions.count - 1)].id
                    session.sessionOrderIndex = 0
                }
                changed = true
            }
            if task.estimatedBlocks != taskDefinitions.count {
                task.estimatedBlocks = taskDefinitions.count
                changed = true
            }
            for definition in taskDefinitions {
                let related = sessions.filter { $0.taskBlockDefinitionID == definition.id }
                if !related.isEmpty {
                    let old = definition.status
                    definition.refreshStatus(sessions: related, taskDefaultMinutes: task.plannedBlockMinutes)
                    changed = changed || old != definition.status
                }
            }
            let completedDefinitionCount = taskDefinitions.filter { $0.status == .done }.count
            if task.completedBlocks != completedDefinitionCount {
                task.completedBlocks = completedDefinitionCount
                changed = true
            }
        }
        if changed { try context.save() }
    }

    private static func sessionOrder(_ left: WorkBlock, _ right: WorkBlock) -> Bool {
        if left.date != right.date { return left.date < right.date }
        if left.period.planningOrder != right.period.planningOrder {
            return left.period.planningOrder < right.period.planningOrder
        }
        return left.id.uuidString < right.id.uuidString
    }

    @MainActor
    static func normalizeTaskIdentifiers(_ tasks: [TodoTask], in context: ModelContext) throws {
        var seen = Set<UUID>()
        var changed = false
        for task in tasks {
            if !seen.insert(task.id).inserted {
                task.id = UUID()
                seen.insert(task.id)
                changed = true
            }
        }
        if changed { try context.save() }
    }

    @MainActor
    static func undo(_ snapshot: PlannerUndoSnapshot, in context: ModelContext) throws {
        let current = try context.fetch(FetchDescriptor<WorkBlock>())
        current.forEach(context.delete)
        for item in snapshot.blocks {
            context.insert(WorkBlock(id: item.id, taskID: item.taskID, date: item.date, period: item.period,
                                     mode: item.mode, estimatedMinutes: item.estimatedMinutes, status: item.status,
                                     locked: item.locked, actualMinutes: item.actualMinutes, notes: item.notes,
                                     splitGroupID: item.splitGroupID,
                                     taskBlockDefinitionID: item.taskBlockDefinitionID,
                                     sessionOrderIndex: item.sessionOrderIndex))
        }
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let metadata = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.taskID, $0) })
        for task in tasks {
            guard let old = metadata[task.id] else { continue }
            task.startBy = old.startBy; task.plannedStart = old.plannedStart
            task.executionRank = old.executionRank; task.plannerReason = old.plannerReason
            task.scheduledDate = old.scheduledDate
            task.hasExplicitDueTime = old.hasExplicitDueTime
            task.deadlineTypeRawValue = old.deadlineTypeRawValue
            task.deadlineTypeSourceRawValue = old.deadlineTypeSourceRawValue
            task.planningPriorityRawValue = old.planningPriorityRawValue
            task.prioritySourceRawValue = old.prioritySourceRawValue
            task.estimatedBlocks = old.estimatedBlocks
            task.manualStartBy = old.manualStartBy
        }
        let currentOverrides = try context.fetch(FetchDescriptor<DayCapacityOverride>())
        currentOverrides.forEach(context.delete)
        for item in snapshot.capacityOverrides {
            context.insert(DayCapacityOverride(id: item.id, date: item.date,
                                               additionalDeepCapacity: item.additionalDeepCapacity,
                                               additionalMediumCapacity: item.additionalMediumCapacity,
                                               additionalFragmentCapacity: item.additionalFragmentCapacity,
                                               reason: item.reason, createdAt: item.createdAt))
        }
        let acknowledgements = try context.fetch(FetchDescriptor<ScheduleConflictAcknowledgement>())
        acknowledgements.forEach(context.delete)
        snapshot.acknowledgedConflictKeys.forEach {
            context.insert(ScheduleConflictAcknowledgement(conflictKey: $0))
        }
        try context.save()
    }

    private static func snapshot(_ block: WorkBlock) -> WorkBlockSnapshot {
        WorkBlockSnapshot(id: block.id, taskID: block.taskID, date: block.date, period: block.period,
                          mode: block.mode, estimatedMinutes: block.estimatedMinutes, status: block.status,
                          locked: block.locked, actualMinutes: block.actualMinutes, notes: block.notes,
                          splitGroupID: block.splitGroupID,
                          taskBlockDefinitionID: block.taskBlockDefinitionID,
                          sessionOrderIndex: block.sessionOrderIndex)
    }

    private static func snapshot(_ override: DayCapacityOverride) -> CapacityOverrideSnapshot {
        CapacityOverrideSnapshot(id: override.id, date: override.date,
                                 additionalDeepCapacity: override.additionalDeepCapacity,
                                 additionalMediumCapacity: override.additionalMediumCapacity,
                                 additionalFragmentCapacity: override.additionalFragmentCapacity,
                                 reason: override.reason, createdAt: override.createdAt)
    }

    @MainActor
    static func captureSnapshot(in context: ModelContext) throws -> PlannerUndoSnapshot {
        let blocks = try context.fetch(FetchDescriptor<WorkBlock>())
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let overrides = try context.fetch(FetchDescriptor<DayCapacityOverride>())
        return PlannerUndoSnapshot(
            blocks: blocks.map(snapshot),
            tasks: tasks.map { TaskPlanSnapshot(taskID: $0.id, startBy: $0.startBy,
                                                plannedStart: $0.plannedStart,
                                                executionRank: $0.executionRank,
                                                plannerReason: $0.plannerReason,
                                                scheduledDate: $0.scheduledDate,
                                                hasExplicitDueTime: $0.hasExplicitDueTime,
                                                deadlineTypeRawValue: $0.deadlineTypeRawValue,
                                                deadlineTypeSourceRawValue: $0.deadlineTypeSourceRawValue,
                                                planningPriorityRawValue: $0.planningPriorityRawValue,
                                                prioritySourceRawValue: $0.prioritySourceRawValue,
                                                estimatedBlocks: $0.estimatedBlocks,
                                                manualStartBy: $0.manualStartBy) },
            capacityOverrides: overrides.map(snapshot),
            acknowledgedConflictKeys: (try context.fetch(FetchDescriptor<ScheduleConflictAcknowledgement>())).map(\.conflictKey)
        )
    }

    private static func planningHorizon(tasks: [TodoTask], now: Date, calendar: Calendar) -> Date {
        let fallback = calendar.date(byAdding: .day, value: 21, to: now) ?? now
        return tasks.compactMap { [$0.scheduledDate, $0.relatedMeetingDate].compactMap { $0 }.max() }.max() ?? fallback
    }

    static func capacityDays(from templates: [DayCapacityTemplate], overrides: [DayCapacityOverride] = [], through end: Date,
                                     now: Date, calendar: Calendar) -> [PlannerCapacityDay] {
        let byWeekday = Dictionary(uniqueKeysWithValues: templates.map { ($0.weekday, $0) })
        let start = calendar.startOfDay(for: now)
        let final = max(calendar.startOfDay(for: end), calendar.date(byAdding: .day, value: 21, to: start) ?? start)
        var date = start; var result: [PlannerCapacityDay] = []
        while date <= final {
            let weekday = calendar.component(.weekday, from: date)
            if let template = byWeekday[weekday] {
                let matching = overrides.filter { calendar.isDate($0.date, inSameDayAs: date) }
                let extraDeep = matching.reduce(0) { $0 + $1.additionalDeepCapacity }
                let extraMedium = matching.reduce(0) { $0 + $1.additionalMediumCapacity }
                let extraFragment = matching.reduce(0) { $0 + $1.additionalFragmentCapacity }
                result.append(PlannerCapacityDay(date: date, kind: template.kind,
                                                 deep: max(0, template.deepCapacity + extraDeep),
                                                 medium: max(0, template.mediumCapacity + extraMedium),
                                                 fragment: max(0, template.fragmentCapacity + extraFragment),
                                                 preferredDeepPeriods: template.preferredDeepPeriods,
                                                 deepPeriodMinutes: template.deepPeriodMinutes
                                                    + Array(repeating: 120, count: max(0, extraDeep)),
                                                 mediumPeriodMinutes: template.mediumPeriodMinutes
                                                    + Array(repeating: 90, count: max(0, extraMedium)),
                                                 fragmentPeriodMinutes: template.fragmentPeriodMinutes
                                                    + Array(repeating: 30, count: max(0, extraFragment))))
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? final.addingTimeInterval(1)
        }
        return result
    }

    private static func planSummary(oldBlocks: [WorkBlockSnapshot], newBlocks: [ProposedWorkBlock],
                                    tasks: [TodoTask], calendar: Calendar) -> [String] {
        let names = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
        let old = Dictionary(grouping: oldBlocks.filter { !$0.locked && $0.status != .done }, by: \.taskID)
        let new = Dictionary(grouping: newBlocks, by: \.taskID)
        return Set(old.keys).union(new.keys).compactMap { id in
            let before = old[id]?.map { calendar.startOfDay(for: $0.date) }.sorted() ?? []
            let after = new[id]?.map { calendar.startOfDay(for: $0.date) }.sorted() ?? []
            guard before != after else { return "\(names[id] ?? "Task") unchanged." }
            guard let first = after.first else { return nil }
            return "\(names[id] ?? "Task") now starts \(first.formatted(date: .abbreviated, time: .omitted))."
        }.sorted()
    }
}
