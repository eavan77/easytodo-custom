import Foundation
import SwiftData

enum ResolutionType: String, CaseIterable, Codable {
    case moveInternalDeadline
    case dayCapacityOverride
    case adjustEstimatedWork
    case splitBlock
    case officialDeadlineAdjustment
    case emergencyOverride
    case keepUnresolved
}

enum ResolutionDisruptionLevel: Int, Comparable, Codable {
    case low, medium, high, exceptional
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct ConflictPreviewChange: Identifiable, Equatable {
    let id = UUID()
    let summary: String
}

struct SplitSession: Equatable {
    let date: Date
    let period: WorkBlockPeriod
    let mode: WorkMode
    let minutes: Int
}

private struct SplitCapacityWindow: Equatable {
    let date: Date
    let period: WorkBlockPeriod
    let mode: WorkMode
    let minutes: Int
}

enum ConflictResolutionAction: Equatable {
    case moveInternalDeadline(taskID: UUID, from: Date, to: Date)
    case addCapacity(date: Date, mode: WorkMode, amount: Int, emergency: Bool)
    case adjustEstimatedWork(taskID: UUID, from: Int, to: Int)
    case adjustBlockEstimate(taskID: UUID, blockID: UUID, fromMinutes: Int, toMinutes: Int)
    case splitBlock(taskID: UUID, fromMinutes: Int, groupID: UUID, sessions: [SplitSession])
    case officialDeadlineAdjustment(taskID: UUID)
    case keepUnresolved(conflictKey: String)
}

struct ConflictResolutionCandidate: Identifiable, Equatable {
    let id: UUID
    let conflictID: String
    let type: ResolutionType
    let affectedTaskIDs: [UUID]
    let title: String
    let summary: String
    let outcome: String
    let tradeoff: String?
    let resolvesConflict: Bool
    let disruptionLevel: ResolutionDisruptionLevel
    let requiresConfirmation: Bool
    let previewChanges: [ConflictPreviewChange]
    let rank: Int
    let action: ConflictResolutionAction
    let output: PlannerOutput

    init(conflictID: String, type: ResolutionType, affectedTaskIDs: [UUID], title: String,
         summary: String, outcome: String, tradeoff: String? = nil, resolvesConflict: Bool,
         disruptionLevel: ResolutionDisruptionLevel, requiresConfirmation: Bool = true,
         previewChanges: [ConflictPreviewChange], rank: Int, action: ConflictResolutionAction,
         output: PlannerOutput) {
        id = UUID(); self.conflictID = conflictID; self.type = type
        self.affectedTaskIDs = affectedTaskIDs; self.title = title; self.summary = summary
        self.outcome = outcome; self.tradeoff = tradeoff; self.resolvesConflict = resolvesConflict
        self.disruptionLevel = disruptionLevel; self.requiresConfirmation = requiresConfirmation
        self.previewChanges = previewChanges; self.rank = rank; self.action = action; self.output = output
    }
}

struct RankedConflictCandidates {
    let all: [ConflictResolutionCandidate]
    var topCandidates: [ConflictResolutionCandidate] { Array(all.prefix(3)) }
    var remainingCandidates: [ConflictResolutionCandidate] { Array(all.dropFirst(3)) }
}

enum ConflictResolver {
    static func candidates(
        for conflict: ScheduleConflict, tasks: [TodoTask], templates: [DayCapacityTemplate],
        overrides: [DayCapacityOverride], blocks: [WorkBlock], currentOutput: PlannerOutput,
        definitions: [TaskBlockDefinition] = [], now: Date = .now, calendar: Calendar = .current
    ) -> RankedConflictCandidates {
        let active = tasks.filter { !$0.isCompleted }
        let affected = active.filter { conflict.taskIDs.contains($0.id) }
        let baseInputs = active.map { input($0, definitions: definitions, sessions: blocks) }
        let locked = lockedInputs(tasks: active, blocks: blocks, calendar: calendar)
        let originalShortfall = shortfall(in: currentOutput)
        var result: [ConflictResolutionCandidate] = []

        for task in affected where task.deadlineType == .internalDeadline && task.deadlineTypeSource == .userSelected {
            guard let oldDate = task.scheduledDate else { continue }
            for offset in 1...7 {
                guard let newDate = calendar.date(byAdding: .day, value: offset, to: oldDate),
                      let candidate = moveCandidate(task: task, to: newDate, conflict: conflict,
                                                    tasks: active, templates: templates, overrides: overrides,
                                                    blocks: blocks, currentOutput: currentOutput,
                                                    definitions: definitions,
                                                    now: now, calendar: calendar),
                      shortfall(in: candidate.output) <= originalShortfall else { continue }
                result.append(candidate)
                break
            }
        }

        if let candidate = capacityCandidate(conflict: conflict, inputs: baseInputs, tasks: active,
                                             templates: templates, overrides: overrides, locked: locked,
                                             currentOutput: currentOutput, now: now, calendar: calendar) {
            result.append(candidate)
        }

        for task in affected {
            if let split = splitCandidate(task: task, conflict: conflict, inputs: baseInputs, tasks: active,
                                          templates: templates, overrides: overrides, blocks: blocks,
                                          locked: locked, currentOutput: currentOutput,
                                          now: now, calendar: calendar) {
                result.append(split)
            }
            let taskDefinitions = definitions.filter { $0.taskID == task.id }
            if !taskDefinitions.isEmpty {
                if let adjusted = adjustedBlockEstimateCandidate(
                    task: task, conflict: conflict, tasks: active, templates: templates,
                    overrides: overrides, sessions: blocks, currentOutput: currentOutput,
                    definitions: definitions, now: now, calendar: calendar
                ) { result.append(adjusted) }
            } else if task.safeEstimatedBlocks > max(1, task.safeCompletedBlocks),
                      let adjusted = adjustedEstimateCandidate(task: task, to: task.safeEstimatedBlocks - 1,
                                                               conflict: conflict, tasks: active,
                                                               templates: templates, overrides: overrides,
                                                               blocks: blocks, currentOutput: currentOutput,
                                                               now: now, calendar: calendar) {
                result.append(adjusted)
            }
        }

        if let official = affected.filter({ $0.deadlineType == .hard }).max(by: {
            $0.priority.schedulingTier < $1.priority.schedulingTier
        }) {
            result.append(ConflictResolutionCandidate(
                conflictID: conflict.conflictKey, type: .officialDeadlineAdjustment,
                affectedTaskIDs: [official.id], title: "Official deadline changed?",
                summary: "Review \(official.title)'s official date or request an adjustment.",
                outcome: "The current workload cannot safely fit without another change.",
                tradeoff: "This does not alter the date automatically.", resolvesConflict: false,
                disruptionLevel: .high, requiresConfirmation: false, previewChanges: [], rank: 60,
                action: .officialDeadlineAdjustment(taskID: official.id), output: currentOutput
            ))
        }

        if let emergency = emergencyCandidate(conflict: conflict, inputs: baseInputs, tasks: active,
                                               templates: templates, overrides: overrides, locked: locked,
                                               currentOutput: currentOutput, now: now, calendar: calendar) {
            result.append(emergency)
        }

        result.append(ConflictResolutionCandidate(
            conflictID: conflict.conflictKey, type: .keepUnresolved,
            affectedTaskIDs: conflict.taskIDs, title: "Keep unresolved",
            summary: "Keep the current deadlines, capacity, and estimates.",
            outcome: "The unscheduled work remains visible for later review.",
            tradeoff: nil, resolvesConflict: false, disruptionLevel: .low,
            requiresConfirmation: false, previewChanges: [], rank: 90,
            action: .keepUnresolved(conflictKey: conflict.conflictKey), output: currentOutput
        ))

        let sorted = result.sorted {
            if $0.resolvesConflict != $1.resolvesConflict { return $0.resolvesConflict }
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.disruptionLevel != $1.disruptionLevel { return $0.disruptionLevel < $1.disruptionLevel }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return RankedConflictCandidates(all: sorted)
    }

    static func moveCandidate(
        task: TodoTask, to newDate: Date, conflict: ScheduleConflict, tasks: [TodoTask],
        templates: [DayCapacityTemplate], overrides: [DayCapacityOverride], blocks: [WorkBlock],
        currentOutput: PlannerOutput, definitions: [TaskBlockDefinition] = [],
        now: Date = .now, calendar: Calendar = .current
    ) -> ConflictResolutionCandidate? {
        guard task.deadlineType == .internalDeadline, task.deadlineTypeSource == .userSelected,
              let oldDate = task.scheduledDate,
              calendar.startOfDay(for: newDate) > calendar.startOfDay(for: oldDate) else { return nil }
        if let meeting = task.relatedMeetingDate,
           calendar.startOfDay(for: newDate) >= calendar.startOfDay(for: meeting) { return nil }
        var inputs = tasks.map { input($0, definitions: definitions, sessions: blocks) }
        guard let index = inputs.firstIndex(where: { $0.id == task.id }) else { return nil }
        inputs[index] = replacing(inputs[index], deadline: newDate)
        let locked = lockedInputs(tasks: tasks, blocks: blocks, calendar: calendar)
        guard let output = try? generate(inputs: inputs, templates: templates, overrides: overrides,
                                         locked: locked, through: newDate, now: now, calendar: calendar),
              shortfall(in: output) < shortfall(in: currentOutput) else { return nil }
        let resolved = shortfall(in: output) == 0
        let dayKind = templates.first { $0.weekday == calendar.component(.weekday, from: newDate) }?.kind
        return ConflictResolutionCandidate(
            conflictID: conflict.conflictKey, type: .moveInternalDeadline, affectedTaskIDs: [task.id],
            title: "Move \(task.title)", summary: "\(short(oldDate)) → \(short(newDate))",
            outcome: resolved ? "Resolves the conflict" : "Reduces the scheduling shortfall",
            tradeoff: dayKind == .free ? "Uses free-day capacity." : "Moves your target date.",
            resolvesConflict: resolved, disruptionLevel: .low,
            previewChanges: changedPlacementLines(before: currentOutput, after: output, tasks: tasks, calendar: calendar),
            rank: disruptionRank(base: 0, for: task),
            action: .moveInternalDeadline(taskID: task.id, from: oldDate, to: newDate), output: output
        )
    }

    static func adjustedEstimateCandidate(
        task: TodoTask, to newCount: Int, conflict: ScheduleConflict, tasks: [TodoTask],
        templates: [DayCapacityTemplate], overrides: [DayCapacityOverride], blocks: [WorkBlock],
        currentOutput: PlannerOutput, definitions: [TaskBlockDefinition] = [],
        now: Date = .now, calendar: Calendar = .current
    ) -> ConflictResolutionCandidate? {
        let oldCount = task.safeEstimatedBlocks
        guard newCount >= task.safeCompletedBlocks, newCount >= 1, newCount != oldCount else { return nil }
        var inputs = tasks.map { input($0, definitions: definitions, sessions: blocks) }
        guard let index = inputs.firstIndex(where: { $0.id == task.id }) else { return nil }
        let remaining = max(0, newCount - task.safeCompletedBlocks)
        inputs[index] = replacing(inputs[index], remainingBlocks: remaining)
        let locked = lockedInputs(tasks: tasks, blocks: blocks, calendar: calendar)
        guard let output = try? generate(inputs: inputs, templates: templates, overrides: overrides,
                                         locked: locked, through: conflict.deadline, now: now, calendar: calendar),
              shortfall(in: output) < shortfall(in: currentOutput) else { return nil }
        return ConflictResolutionCandidate(
            conflictID: conflict.conflictKey, type: .adjustEstimatedWork, affectedTaskIDs: [task.id],
            title: "Adjust estimated work", summary: "\(task.title): \(oldCount) → \(newCount) blocks",
            outcome: shortfall(in: output) == 0 ? "Resolves the conflict" : "Reduces the scheduling shortfall",
            tradeoff: "Changes the planner's estimate; it does not automatically reduce the real work.",
            resolvesConflict: shortfall(in: output) == 0, disruptionLevel: .medium,
            previewChanges: changedPlacementLines(before: currentOutput, after: output, tasks: tasks, calendar: calendar),
            rank: disruptionRank(base: 35, for: task),
            action: .adjustEstimatedWork(taskID: task.id, from: oldCount, to: newCount), output: output
        )
    }

    private static func adjustedBlockEstimateCandidate(
        task: TodoTask, conflict: ScheduleConflict, tasks: [TodoTask], templates: [DayCapacityTemplate],
        overrides: [DayCapacityOverride], sessions: [WorkBlock], currentOutput: PlannerOutput,
        definitions: [TaskBlockDefinition], now: Date, calendar: Calendar
    ) -> ConflictResolutionCandidate? {
        let taskDefinitions = definitions.filter { $0.taskID == task.id }.sorted { $0.orderIndex < $1.orderIndex }
        let preferred = conflict.blockDefinitionID.flatMap { id in taskDefinitions.first { $0.id == id } }
        guard let definition = preferred ?? taskDefinitions.last(where: { $0.status != .done }),
              let oldMinutes = definition.estimatedMinutes else { return nil }
        let completedMinutes = sessions.filter {
            $0.taskBlockDefinitionID == definition.id && $0.status == .done
        }.reduce(0) { $0 + $1.estimatedMinutes }
        let lowerBound = max(completedMinutes, definition.minimumSessionMinutes ?? 15, 15)
        guard oldMinutes > lowerBound else { return nil }
        let originalShortfall = shortfall(in: currentOutput)
        let locked = lockedInputs(tasks: tasks, blocks: sessions, calendar: calendar)

        for proposed in stride(from: oldMinutes - 15, through: lowerBound, by: -15) {
            var inputs = tasks.map { input($0, definitions: definitions, sessions: sessions) }
            guard let taskIndex = inputs.firstIndex(where: { $0.id == task.id }),
                  let blockIndex = inputs[taskIndex].blocks.firstIndex(where: { $0.id == definition.id })
            else { continue }
            var adjustedBlocks = inputs[taskIndex].blocks
            let existing = adjustedBlocks[blockIndex]
            adjustedBlocks[blockIndex] = PlannerBlockInput(
                id: existing.id, orderIndex: existing.orderIndex, title: existing.title,
                remainingMinutes: max(0, proposed - completedMinutes), estimatedMinutes: proposed,
                splittable: existing.splittable, minimumSessionMinutes: existing.minimumSessionMinutes
            )
            inputs[taskIndex] = replacingBlocks(inputs[taskIndex], blocks: adjustedBlocks)
            guard let output = try? generate(inputs: inputs, templates: templates, overrides: overrides,
                                             locked: locked, through: conflict.deadline,
                                             now: now, calendar: calendar),
                  shortfall(in: output) < originalShortfall else { continue }
            return ConflictResolutionCandidate(
                conflictID: conflict.conflictKey, type: .adjustEstimatedWork,
                affectedTaskIDs: [task.id], title: "Adjust \(definition.title)",
                summary: "\(oldMinutes) min → \(proposed) min",
                outcome: shortfall(in: output) == 0 ? "Resolves the conflict" : "Reduces the scheduling shortfall",
                tradeoff: "Changes this block's estimate only; confirmation is required.",
                resolvesConflict: shortfall(in: output) == 0, disruptionLevel: .medium,
                previewChanges: changedPlacementLines(before: currentOutput, after: output,
                                                      tasks: tasks, calendar: calendar),
                rank: disruptionRank(base: 35, for: task),
                action: .adjustBlockEstimate(taskID: task.id, blockID: definition.id,
                                             fromMinutes: oldMinutes, toMinutes: proposed),
                output: output
            )
        }
        return nil
    }

    private static func capacityCandidate(
        conflict: ScheduleConflict, inputs: [PlannerTaskInput], tasks: [TodoTask], templates: [DayCapacityTemplate],
        overrides: [DayCapacityOverride], locked: [PlannerLockedBlock], currentOutput: PlannerOutput,
        now: Date, calendar: Calendar
    ) -> ConflictResolutionCandidate? {
        let start = calendar.startOfDay(for: now)
        let templateByWeekday = Dictionary(uniqueKeysWithValues: templates.map { ($0.weekday, $0) })
        var date = start
        while date <= calendar.startOfDay(for: conflict.deadline) {
            if let template = templateByWeekday[calendar.component(.weekday, from: date)] {
                let temporary = capacityOverride(date: date, mode: conflict.mode, amount: 1,
                                                 reason: "Schedule conflict resolution")
                if let output = try? generate(inputs: inputs, templates: templates, overrides: overrides + [temporary],
                                              locked: locked, through: conflict.deadline, now: now, calendar: calendar),
                   shortfall(in: output) < shortfall(in: currentOutput) {
                    let normal = capacity(template, mode: conflict.mode)
                    return ConflictResolutionCandidate(
                        conflictID: conflict.conflictKey, type: .dayCapacityOverride,
                        affectedTaskIDs: conflict.taskIDs, title: "Add 1 extra \(conflict.mode.title) block",
                        summary: "\(weekdayDate(date)) · Capacity \(normal) → \(normal + 1)",
                        outcome: shortfall(in: output) == 0 ? "Resolves the conflict" : "Reduces the scheduling shortfall",
                        tradeoff: "This date only; the recurring template is unchanged.",
                        resolvesConflict: shortfall(in: output) == 0, disruptionLevel: .low,
                        previewChanges: changedPlacementLines(before: currentOutput, after: output, tasks: tasks, calendar: calendar),
                        rank: 15, action: .addCapacity(date: date, mode: conflict.mode, amount: 1, emergency: false), output: output
                    )
                }
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? conflict.deadline.addingTimeInterval(1)
        }
        return nil
    }

    private static func splitCandidate(
        task: TodoTask, conflict: ScheduleConflict, inputs: [PlannerTaskInput], tasks: [TodoTask],
        templates: [DayCapacityTemplate], overrides: [DayCapacityOverride], blocks: [WorkBlock],
        locked: [PlannerLockedBlock], currentOutput: PlannerOutput, now: Date, calendar: Calendar
    ) -> ConflictResolutionCandidate? {
        guard task.splittable ?? true, task.remainingBlocks > 0 else { return nil }
        let originalMinutes = task.plannedBlockMinutes
        let minimum = max(15, task.minimumBlockMinutes ?? 15)
        guard originalMinutes >= minimum * 2 else { return nil }
        let sessionMinutes = [originalMinutes / 2, originalMinutes - (originalMinutes / 2)]
        guard sessionMinutes.allSatisfy({ $0 >= minimum }) else { return nil }
        let days = PlannerCoordinator.capacityDays(from: templates, overrides: overrides,
                                                   through: conflict.deadline, now: now, calendar: calendar)
            .filter { $0.date <= calendar.startOfDay(for: conflict.deadline) }
        var windows = days.flatMap { splitCapacityWindows(for: $0, calendar: calendar) }
        func reserve(date: Date, period: WorkBlockPeriod, mode: WorkMode) {
            let day = calendar.startOfDay(for: date)
            if let index = windows.firstIndex(where: {
                $0.date == day && $0.period == period && $0.mode == mode
            }) { windows.remove(at: index) }
        }
        currentOutput.blocks.forEach { reserve(date: $0.date, period: $0.period, mode: $0.mode) }
        locked.forEach { reserve(date: $0.date, period: $0.period, mode: $0.mode) }
        var sessions: [SplitSession] = []
        for minutes in sessionMinutes {
            guard let index = windows.indices.filter({
                windows[$0].mode == task.workMode && windows[$0].minutes >= minutes
            }).min(by: { windows[$0].minutes < windows[$1].minutes }) else { return nil }
            let window = windows.remove(at: index)
            sessions.append(SplitSession(date: window.date, period: window.period,
                                         mode: task.workMode, minutes: minutes))
        }
        guard var taskInput = inputs.first(where: { $0.id == task.id }) else { return nil }
        taskInput = replacing(taskInput, remainingBlocks: taskInput.remainingBlocks + 1)
        var candidateInputs = inputs.filter { $0.id != task.id }; candidateInputs.append(taskInput)
        let splitLocked = sessions.map {
            PlannerLockedBlock(taskID: task.id, date: $0.date, mode: $0.mode,
                               period: $0.period, estimatedMinutes: $0.minutes)
        }
        guard var output = try? generate(inputs: candidateInputs, templates: templates, overrides: overrides,
                                         locked: locked + splitLocked, through: conflict.deadline,
                                         now: now, calendar: calendar),
              shortfall(in: output) < shortfall(in: currentOutput) else { return nil }
        output = PlannerOutput(blocks: (output.blocks + sessions.map {
            ProposedWorkBlock(taskID: task.id, date: $0.date, period: $0.period, mode: $0.mode, minutes: $0.minutes)
        }).sorted(by: { ($0.date, $0.period.planningOrder) < ($1.date, $1.period.planningOrder) }),
                               taskMetadata: output.taskMetadata, conflicts: output.conflicts)
        let remainingShortfall = shortfall(in: output)
        let reduction = shortfall(in: currentOutput) - remainingShortfall
        let shape = sessionMinutes[0] == sessionMinutes[1]
            ? "2 × \(sessionMinutes[0]) min \(task.workMode.title) sessions"
            : "\(sessionMinutes[0]) + \(sessionMinutes[1]) min \(task.workMode.title) sessions"
        let groupID = UUID()
        return ConflictResolutionCandidate(
            conflictID: conflict.conflictKey, type: .splitBlock, affectedTaskIDs: [task.id],
            title: "Split one \(task.workMode.title) block",
            summary: "\(originalMinutes) min → \(shape)",
            outcome: remainingShortfall == 0 ? "Resolves the conflict" : "Reduces conflict by \(reduction) session\(reduction == 1 ? "" : "s")",
            tradeoff: "Total work unchanged.", resolvesConflict: remainingShortfall == 0,
            disruptionLevel: .medium,
            previewChanges: changedPlacementLines(before: currentOutput, after: output, tasks: tasks, calendar: calendar),
            rank: 25, action: .splitBlock(taskID: task.id, fromMinutes: originalMinutes,
                                          groupID: groupID, sessions: sessions), output: output
        )
    }

    private static func emergencyCandidate(
        conflict: ScheduleConflict, inputs: [PlannerTaskInput], tasks: [TodoTask], templates: [DayCapacityTemplate],
        overrides: [DayCapacityOverride], locked: [PlannerLockedBlock], currentOutput: PlannerOutput,
        now: Date, calendar: Calendar
    ) -> ConflictResolutionCandidate? {
        let date = calendar.startOfDay(for: conflict.deadline)
        let amount = max(1, conflict.required - conflict.available)
        let temporary = capacityOverride(date: date, mode: conflict.mode, amount: amount, reason: "Emergency protected-time override")
        guard let output = try? generate(inputs: inputs, templates: templates, overrides: overrides + [temporary],
                                         locked: locked, through: conflict.deadline, now: now, calendar: calendar),
              shortfall(in: output) < shortfall(in: currentOutput) else { return nil }
        return ConflictResolutionCandidate(
            conflictID: conflict.conflictKey, type: .emergencyOverride,
            affectedTaskIDs: conflict.taskIDs, title: "Emergency override",
            summary: "Use protected 21:00–22:00 time on \(short(date))",
            outcome: shortfall(in: output) == 0 ? "Resolves the conflict" : "Reduces the scheduling shortfall",
            tradeoff: "Overrides protected rest once; the recurring protection remains unchanged.",
            resolvesConflict: shortfall(in: output) == 0, disruptionLevel: .exceptional,
            previewChanges: changedPlacementLines(before: currentOutput, after: output, tasks: tasks, calendar: calendar),
            rank: 70, action: .addCapacity(date: date, mode: conflict.mode, amount: amount, emergency: true), output: output
        )
    }

    private static func generate(inputs: [PlannerTaskInput], templates: [DayCapacityTemplate],
                                 overrides: [DayCapacityOverride], locked: [PlannerLockedBlock], through: Date,
                                 now: Date, calendar: Calendar) throws -> PlannerOutput {
        let latest = inputs.compactMap { [$0.deadline, $0.meetingDate].compactMap { $0 }.max() }.max() ?? through
        let days = PlannerCoordinator.capacityDays(from: templates, overrides: overrides,
                                                    through: max(latest, through), now: now, calendar: calendar)
        return try DeterministicPlanner.generatePlan(tasks: inputs, dayCapacities: days,
                                                     lockedBlocks: locked, now: now, calendar: calendar)
    }

    private static func input(_ task: TodoTask) -> PlannerTaskInput {
        input(task, definitions: [], sessions: [])
    }

    private static func input(_ task: TodoTask, definitions: [TaskBlockDefinition],
                              sessions: [WorkBlock]) -> PlannerTaskInput {
        let logical = definitions.filter { $0.taskID == task.id }.sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { definition -> PlannerBlockInput? in
                let completed = sessions.filter { $0.taskBlockDefinitionID == definition.id && $0.status == .done }
                    .reduce(0) { $0 + $1.estimatedMinutes }
                let total = definition.effectiveMinutes(taskDefault: task.plannedBlockMinutes)
                guard definition.status != .done, total > completed else { return nil }
                return PlannerBlockInput(id: definition.id, orderIndex: definition.orderIndex,
                                         title: definition.title, remainingMinutes: total - completed,
                                         estimatedMinutes: definition.estimatedMinutes,
                                         splittable: definition.splittable,
                                         minimumSessionMinutes: max(1, definition.minimumSessionMinutes ?? min(15, total)))
            }
        return PlannerTaskInput(id: task.id, title: task.title, deadline: task.scheduledDate,
                         deadlineType: task.deadlineType, mode: task.workMode, size: task.taskSize,
                         energy: task.energyDemand, remainingBlocks: task.remainingBlocks,
                         blockMinutes: task.plannedBlockMinutes,
                         splittable: task.splittable ?? true, uncertainty: task.uncertainty,
                         dependencies: task.dependencyIDs, meetingDate: task.relatedMeetingDate,
                         priority: task.priority, manualPriority: task.manualPriority,
                         manualStartBy: task.manualStartBy, recommendedStartBy: task.startBy,
                         blocks: logical.isEmpty ? nil : logical)
    }

    private static func lockedInputs(tasks: [TodoTask], blocks: [WorkBlock], calendar: Calendar) -> [PlannerLockedBlock] {
        let lockedTasks = Set(tasks.filter(\.isPlannerLocked).map(\.id))
        return blocks.filter { ($0.locked || lockedTasks.contains($0.taskID)) && $0.status != .done }.map {
            PlannerLockedBlock(taskID: $0.taskID, date: calendar.startOfDay(for: $0.date), mode: $0.mode,
                               period: $0.period, estimatedMinutes: $0.estimatedMinutes,
                               blockDefinitionID: $0.taskBlockDefinitionID)
        }
    }

    private static func replacing(_ value: PlannerTaskInput, deadline: Date? = nil,
                                  remainingBlocks: Int? = nil) -> PlannerTaskInput {
        PlannerTaskInput(id: value.id, title: value.title, deadline: deadline ?? value.deadline,
                         deadlineType: value.deadlineType, mode: value.mode, size: value.size,
                         energy: value.energy, remainingBlocks: remainingBlocks ?? value.remainingBlocks,
                         blockMinutes: value.blockMinutes, splittable: value.splittable,
                         uncertainty: value.uncertainty, dependencies: value.dependencies,
                         meetingDate: value.meetingDate, priority: value.priority,
                         manualPriority: value.manualPriority, manualStartBy: value.manualStartBy,
                         recommendedStartBy: value.recommendedStartBy,
                         blocks: value.usesLegacySessionSemantics ? nil : value.blocks)
    }

    private static func replacingBlocks(_ value: PlannerTaskInput,
                                        blocks: [PlannerBlockInput]) -> PlannerTaskInput {
        PlannerTaskInput(id: value.id, title: value.title, deadline: value.deadline,
                         deadlineType: value.deadlineType, mode: value.mode, size: value.size,
                         energy: value.energy, remainingBlocks: blocks.count,
                         blockMinutes: value.blockMinutes, splittable: value.splittable,
                         uncertainty: value.uncertainty, dependencies: value.dependencies,
                         meetingDate: value.meetingDate, priority: value.priority,
                         manualPriority: value.manualPriority, manualStartBy: value.manualStartBy,
                         recommendedStartBy: value.recommendedStartBy, blocks: blocks)
    }

    static func shortfall(in output: PlannerOutput) -> Int {
        output.conflicts.reduce(0) { $0 + max(0, $1.required - $1.available) }
    }

    private static func disruptionRank(base: Int, for task: TodoTask) -> Int {
        let penalty: Int
        switch task.priority {
        case .low: penalty = 0
        case .normal: penalty = 15
        case .high: penalty = 30
        case .critical: penalty = 45
        }
        return base + penalty
    }

    private static func changedPlacementLines(before: PlannerOutput, after: PlannerOutput,
                                              tasks: [TodoTask], calendar: Calendar) -> [ConflictPreviewChange] {
        let names = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) })
        let beforeByTask = Dictionary(grouping: before.blocks, by: \.taskID)
        let afterByTask = Dictionary(grouping: after.blocks, by: \.taskID)
        return Set(beforeByTask.keys).union(afterByTask.keys).sorted { (names[$0] ?? "") < (names[$1] ?? "") }.compactMap { id in
            let old = beforeByTask[id, default: []].map { "\(short($0.date)) · \($0.period.title)" }.sorted()
            let new = afterByTask[id, default: []].map { "\(short($0.date)) · \($0.period.title)" }.sorted()
            guard old != new else { return nil }
            return ConflictPreviewChange(summary: "\(names[id] ?? "Task"): \(old.isEmpty ? "Unscheduled" : old.joined(separator: ", ")) → \(new.isEmpty ? "Unscheduled" : new.joined(separator: ", "))")
        }
    }

    private static func capacityOverride(date: Date, mode: WorkMode, amount: Int, reason: String) -> DayCapacityOverride {
        DayCapacityOverride(date: date, additionalDeepCapacity: mode == .deep ? amount : 0,
                            additionalMediumCapacity: mode == .medium ? amount : 0,
                            additionalFragmentCapacity: mode == .fragmentable ? amount : 0, reason: reason)
    }

    private static func splitCapacityWindows(for day: PlannerCapacityDay,
                                             calendar: Calendar) -> [SplitCapacityWindow] {
        func period(_ mode: WorkMode, _ ordinal: Int) -> WorkBlockPeriod {
            switch mode {
            case .deep:
                if day.preferredDeepPeriods.indices.contains(ordinal) { return day.preferredDeepPeriods[ordinal] }
                return day.kind == .free ? (ordinal == 0 ? .deep1 : .deep2) : .evening
            case .medium:
                if day.kind == .school { return .evening }
                return ordinal == 0 ? .morning : .afternoon
            case .fragmentable:
                return day.kind == .school ? .schoolFragment : .flexible
            }
        }
        let date = calendar.startOfDay(for: day.date)
        func make(_ mode: WorkMode, _ minutes: [Int]) -> [SplitCapacityWindow] {
            minutes.enumerated().map {
                SplitCapacityWindow(date: date, period: period(mode, $0.offset), mode: mode,
                                    minutes: max(1, $0.element))
            }
        }
        return make(.deep, day.deepPeriodMinutes) + make(.medium, day.mediumPeriodMinutes)
            + make(.fragmentable, day.fragmentPeriodMinutes)
    }

    private static func capacity(_ template: DayCapacityTemplate, mode: WorkMode) -> Int {
        switch mode { case .deep: template.deepCapacity; case .medium: template.mediumCapacity; case .fragmentable: template.fragmentCapacity }
    }

    private static func short(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }
    private static func weekdayDate(_ date: Date) -> String { date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
}

extension PlannerCoordinator {
    @MainActor
    static func apply(_ candidate: ConflictResolutionCandidate, in context: ModelContext,
                      now: Date = .now, calendar: Calendar = .current) throws -> AppliedPlan {
        let before = try captureSnapshot(in: context)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        if candidate.type != .keepUnresolved {
            let acknowledgements = try context.fetch(FetchDescriptor<ScheduleConflictAcknowledgement>())
            acknowledgements.filter { $0.conflictKey == candidate.conflictID }.forEach(context.delete)
        }
        switch candidate.action {
        case let .moveInternalDeadline(taskID, _, to):
            guard let task = tasks.first(where: { $0.id == taskID }),
                  task.deadlineType == .internalDeadline, task.deadlineTypeSource == .userSelected else {
                throw PlannerResolutionError.taskNoLongerEligible
            }
            task.setDueDate(to, includesTime: task.hasExplicitDueTime, calendar: calendar)
        case let .addCapacity(date, mode, amount, emergency):
            context.insert(DayCapacityOverride(date: date,
                                               additionalDeepCapacity: mode == .deep ? amount : 0,
                                               additionalMediumCapacity: mode == .medium ? amount : 0,
                                               additionalFragmentCapacity: mode == .fragmentable ? amount : 0,
                                               reason: emergency ? "Emergency protected-time override" : "Allowed once to resolve a schedule conflict"))
        case let .adjustEstimatedWork(taskID, _, to):
            guard let task = tasks.first(where: { $0.id == taskID }) else { throw PlannerResolutionError.taskNoLongerEligible }
            task.estimatedBlocks = max(task.safeCompletedBlocks, to)
        case let .adjustBlockEstimate(taskID, blockID, _, toMinutes):
            let definitions = try context.fetch(FetchDescriptor<TaskBlockDefinition>())
            guard tasks.contains(where: { $0.id == taskID }),
                  let definition = definitions.first(where: { $0.id == blockID && $0.taskID == taskID }) else {
                throw PlannerResolutionError.taskNoLongerEligible
            }
            definition.estimatedMinutes = max(1, toMinutes)
            definition.updatedAt = .now
        case let .splitBlock(taskID, _, groupID, sessions):
            guard let task = tasks.first(where: { $0.id == taskID }), task.splittable ?? true else {
                throw PlannerResolutionError.taskNoLongerEligible
            }
            task.estimatedBlocks = task.safeEstimatedBlocks + 1
            sessions.forEach { session in
                context.insert(WorkBlock(taskID: taskID, date: session.date, period: session.period,
                                         mode: session.mode, estimatedMinutes: session.minutes,
                                         status: .planned, locked: true,
                                         notes: "Split from one \(candidate.summary)", splitGroupID: groupID))
            }
        case .officialDeadlineAdjustment:
            throw PlannerResolutionError.informationalAction
        case let .keepUnresolved(conflictKey):
            let existing = try context.fetch(FetchDescriptor<ScheduleConflictAcknowledgement>())
            if !existing.contains(where: { $0.conflictKey == conflictKey }) {
                context.insert(ScheduleConflictAcknowledgement(conflictKey: conflictKey))
            }
            try context.save()
            return AppliedPlan(output: candidate.output, undoSnapshot: before,
                               summary: ["Conflict acknowledged. No schedule inputs were changed."])
        }
        try context.save()
        let applied = try replan(in: context, now: now, calendar: calendar)
        return AppliedPlan(output: applied.output, undoSnapshot: before,
                           summary: resolutionSummary(candidate.action, tasks: tasks, resolved: applied.output.conflicts.isEmpty))
    }

    private static func resolutionSummary(_ action: ConflictResolutionAction, tasks: [TodoTask], resolved: Bool) -> [String] {
        var lines: [String]
        switch action {
        case let .moveInternalDeadline(id, from, to):
            lines = ["\(tasks.first { $0.id == id }?.title ?? "Task"): \(from.formatted(date: .abbreviated, time: .omitted)) → \(to.formatted(date: .abbreviated, time: .omitted))."]
        case let .addCapacity(date, mode, amount, emergency):
            lines = ["\(date.formatted(date: .abbreviated, time: .omitted)): \(amount) extra \(mode.title.lowercased()) block allowed\(emergency ? " using protected time" : "") once."]
        case let .adjustEstimatedWork(id, from, to):
            lines = ["\(tasks.first { $0.id == id }?.title ?? "Task"): estimate changed from \(from) to \(to) blocks."]
        case let .adjustBlockEstimate(id, _, from, to):
            lines = ["\(tasks.first { $0.id == id }?.title ?? "Task"): block estimate changed from \(from) to \(to) minutes."]
        case let .splitBlock(id, _, _, sessions):
            lines = ["\(tasks.first { $0.id == id }?.title ?? "Task"): one block split into \(sessions.count) shorter sessions."]
        case .officialDeadlineAdjustment, .keepUnresolved:
            lines = []
        }
        lines.append(resolved ? "Conflict resolved." : "Some scheduling conflict remains.")
        return lines
    }
}

enum PlannerResolutionError: LocalizedError {
    case taskNoLongerEligible
    case informationalAction
    var errorDescription: String? {
        switch self {
        case .taskNoLongerEligible: "The task changed after this preview. Run Replan and choose again."
        case .informationalAction: "Review the official deadline in Task Detail."
        }
    }
}
