import Foundation

struct PlannerBlockInput: Equatable {
    let id: UUID
    let orderIndex: Int
    let title: String
    let remainingMinutes: Int
    let estimatedMinutes: Int?
    let splittable: Bool
    let minimumSessionMinutes: Int
}

struct PlannerTaskInput: Equatable {
    let id: UUID
    let title: String
    let deadline: Date?
    let deadlineType: DeadlineType
    let mode: WorkMode
    let size: TaskSize
    let energy: EnergyDemand
    let remainingBlocks: Int
    let blockMinutes: Int
    let splittable: Bool
    let uncertainty: PlanningUncertainty
    let dependencies: [UUID]
    let meetingDate: Date?
    let priority: TaskPriority
    let manualPriority: Int?
    let manualStartBy: Date?
    let recommendedStartBy: Date?
    let blocks: [PlannerBlockInput]
    let usesLegacySessionSemantics: Bool

    init(id: UUID, title: String, deadline: Date?, deadlineType: DeadlineType, mode: WorkMode,
         size: TaskSize, energy: EnergyDemand, remainingBlocks: Int, blockMinutes: Int,
         splittable: Bool, uncertainty: PlanningUncertainty, dependencies: [UUID],
         meetingDate: Date?, priority: TaskPriority = .normal, manualPriority: Int?,
         manualStartBy: Date? = nil, recommendedStartBy: Date? = nil,
         blocks: [PlannerBlockInput]? = nil) {
        self.id = id; self.title = title; self.deadline = deadline; self.deadlineType = deadlineType
        self.mode = mode; self.size = size; self.energy = energy; self.remainingBlocks = remainingBlocks
        self.blockMinutes = blockMinutes; self.splittable = splittable; self.uncertainty = uncertainty
        self.dependencies = dependencies; self.meetingDate = meetingDate; self.priority = priority
        self.manualPriority = manualPriority
        self.manualStartBy = manualStartBy
        self.recommendedStartBy = recommendedStartBy
        self.usesLegacySessionSemantics = blocks == nil
        self.blocks = blocks ?? (0..<max(0, remainingBlocks)).map {
            PlannerBlockInput(id: UUID(), orderIndex: $0, title: "Block \($0 + 1)",
                              remainingMinutes: blockMinutes, estimatedMinutes: nil,
                              splittable: false, minimumSessionMinutes: min(15, blockMinutes))
        }
    }
}

struct PlannerCapacityDay: Equatable {
    let date: Date
    let kind: DayTemplateKind
    let deep: Int
    let medium: Int
    let fragment: Int
    let preferredDeepPeriods: [WorkBlockPeriod]
    let deepPeriodMinutes: [Int]
    let mediumPeriodMinutes: [Int]
    let fragmentPeriodMinutes: [Int]

    init(date: Date, kind: DayTemplateKind, deep: Int, medium: Int, fragment: Int,
         preferredDeepPeriods: [WorkBlockPeriod], deepPeriodMinutes: [Int]? = nil,
         mediumPeriodMinutes: [Int]? = nil, fragmentPeriodMinutes: [Int]? = nil) {
        self.date = date; self.kind = kind; self.deep = deep; self.medium = medium; self.fragment = fragment
        self.preferredDeepPeriods = preferredDeepPeriods
        self.deepPeriodMinutes = Self.normalized(deepPeriodMinutes, count: deep, defaultMinutes: 120)
        self.mediumPeriodMinutes = Self.normalized(mediumPeriodMinutes, count: medium, defaultMinutes: 90)
        self.fragmentPeriodMinutes = Self.normalized(fragmentPeriodMinutes, count: fragment, defaultMinutes: 30)
    }

    private static func normalized(_ values: [Int]?, count: Int, defaultMinutes: Int) -> [Int] {
        let valid = (values ?? []).filter { $0 > 0 }
        return Array(valid.prefix(max(0, count)))
            + Array(repeating: defaultMinutes, count: max(0, count - valid.count))
    }
}

struct PlannerLockedBlock: Equatable {
    let taskID: UUID
    let date: Date
    let mode: WorkMode
    let period: WorkBlockPeriod
    let estimatedMinutes: Int
    let blockDefinitionID: UUID?

    init(taskID: UUID, date: Date, mode: WorkMode, period: WorkBlockPeriod, estimatedMinutes: Int = 60,
         blockDefinitionID: UUID? = nil) {
        self.taskID = taskID; self.date = date; self.mode = mode; self.period = period
        self.estimatedMinutes = estimatedMinutes
        self.blockDefinitionID = blockDefinitionID
    }
}

struct ProposedWorkBlock: Equatable {
    let taskID: UUID
    var date: Date
    var period: WorkBlockPeriod
    let mode: WorkMode
    let minutes: Int
    let blockDefinitionID: UUID?
    let sessionOrderIndex: Int

    init(taskID: UUID, date: Date, period: WorkBlockPeriod, mode: WorkMode, minutes: Int,
         blockDefinitionID: UUID? = nil, sessionOrderIndex: Int = 0) {
        self.taskID = taskID; self.date = date; self.period = period; self.mode = mode; self.minutes = minutes
        self.blockDefinitionID = blockDefinitionID; self.sessionOrderIndex = sessionOrderIndex
    }
}

enum ScheduleConflictReason: String, Equatable {
    case capacity
    case manualStartBy
    case nonSplittableBlock
    case minimumSession
}

struct ScheduleConflict: Identifiable, Equatable {
    let id = UUID()
    let mode: WorkMode
    let deadline: Date
    let required: Int
    let available: Int
    let taskIDs: [UUID]
    let taskTitles: [String]
    let reason: ScheduleConflictReason
    let blockDefinitionID: UUID?

    init(mode: WorkMode, deadline: Date, required: Int, available: Int,
         taskIDs: [UUID], taskTitles: [String], reason: ScheduleConflictReason = .capacity,
         blockDefinitionID: UUID? = nil) {
        self.mode = mode; self.deadline = deadline; self.required = required; self.available = available
        self.taskIDs = taskIDs; self.taskTitles = taskTitles; self.reason = reason
        self.blockDefinitionID = blockDefinitionID
    }

    var conflictKey: String {
        let day = Int(deadline.timeIntervalSince1970 / 86_400)
        return "\(mode.rawValue)|\(day)|\(taskIDs.map(\.uuidString).sorted().joined(separator: ","))"
    }

    var recommendation: String {
        "Move a soft/internal deadline first; otherwise reduce scope or manually allow one additional \(mode.title.lowercased()) block."
    }
}

struct TaskPlanMetadata: Equatable {
    let startBy: Date?
    let plannedStart: Date?
    let executionRank: Int
    let reason: String
}

struct PlannerOutput: Equatable {
    let blocks: [ProposedWorkBlock]
    let taskMetadata: [UUID: TaskPlanMetadata]
    let conflicts: [ScheduleConflict]
}

private struct TaskSchedulingWindow {
    var preferredFinishDate: Date
    var latestEligibleDate: Date
}

private struct CapacityWindow: Equatable {
    let mode: WorkMode
    let period: WorkBlockPeriod
    let minutes: Int
    let isCriticalFlex: Bool

    init(mode: WorkMode, period: WorkBlockPeriod, minutes: Int, isCriticalFlex: Bool = false) {
        self.mode = mode
        self.period = period
        self.minutes = minutes
        self.isCriticalFlex = isCriticalFlex
    }
}

private struct AvailableSlot: Equatable {
    let date: Date
    let index: Int
    let window: CapacityWindow
}

private struct UnscheduledBlock {
    let task: PlannerTaskInput
    let block: PlannerBlockInput
    let deadline: Date
    let reason: ScheduleConflictReason
}

enum PlannerError: Error, Equatable, LocalizedError {
    case dependencyCycle([UUID])
    case duplicateTaskIdentifiers

    var errorDescription: String? {
        switch self {
        case .dependencyCycle: "The task dependency chain contains a cycle. Remove one dependency before replanning."
        case .duplicateTaskIdentifiers: "Two tasks share a planner identifier. Reopen the app to repair legacy task identifiers."
        }
    }
}

enum DeterministicPlanner {
    static func generatePlan(
        tasks: [PlannerTaskInput],
        dayCapacities: [PlannerCapacityDay],
        lockedBlocks: [PlannerLockedBlock],
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> PlannerOutput {
        let active = tasks.filter { $0.remainingBlocks > 0 }
        guard Set(active.map(\.id)).count == active.count else { throw PlannerError.duplicateTaskIdentifiers }
        try rejectCycles(in: active)

        let today = calendar.startOfDay(for: now)
        let capacities = dayCapacities
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
        let capacityByDay = Dictionary(uniqueKeysWithValues: capacities.map { (calendar.startOfDay(for: $0.date), $0) })
        var remaining = Dictionary(uniqueKeysWithValues: capacities.map {
            (calendar.startOfDay(for: $0.date), capacityWindows(for: $0))
        })
        for block in lockedBlocks where block.date >= today {
            let day = calendar.startOfDay(for: block.date)
            guard var windows = remaining[day] else { continue }
            let matchingPeriod = windows.firstIndex {
                $0.mode == block.mode && $0.period == block.period && $0.minutes >= block.estimatedMinutes
            }
            let anyCompatible = windows.firstIndex { $0.mode == block.mode && $0.minutes >= block.estimatedMinutes }
            if let index = matchingPeriod ?? anyCompatible ?? windows.firstIndex(where: { $0.mode == block.mode }) {
                windows.remove(at: index)
            }
            remaining[day] = windows
        }

        let taskByID = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })
        let schedulingWindows = effectiveSchedulingWindows(active, taskByID: taskByID, today: today, calendar: calendar)
        let preferredDates = schedulingWindows.mapValues(\.preferredFinishDate)
        let latestEligibleDates = schedulingWindows.mapValues(\.latestEligibleDate)
        let effectivePriorityTiers = effectivePriorityTiers(active)
        let ordered = topologicallyOrdered(active, targetDates: preferredDates,
                                           effectivePriorityTiers: effectivePriorityTiers)
        var blocks: [ProposedWorkBlock] = []
        var unscheduled: [UnscheduledBlock] = []

        for task in ordered {
            let window = schedulingWindows[task.id]
                ?? TaskSchedulingWindow(preferredFinishDate: capacities.last?.date ?? today,
                                        latestEligibleDate: capacities.last?.date ?? today)
            let usesCriticalFlex = task.priority == .critical
                && task.deadlineType == .hard
                && task.mode == .deep
            if usesCriticalFlex {
                addCriticalFreeDayFlex(to: &remaining, capacities: capacities,
                                       through: window.latestEligibleDate, calendar: calendar)
            }
            if task.usesLegacySessionSemantics {
                let lockedCount = lockedBlocks.filter { $0.taskID == task.id }.count
                let required = max(0, task.remainingBlocks - lockedCount)
                var placed = 0
                let eligible = capacities.filter { $0.date <= window.latestEligibleDate }
                let preferred = eligible.filter { $0.date <= window.preferredFinishDate }
                let fallback = eligible.filter { $0.date > window.preferredFinishDate }
                func allocate(_ days: [PlannerCapacityDay]) {
                    for day in days.reversed() where placed < required {
                        let normalized = calendar.startOfDay(for: day.date)
                        guard var windows = remaining[normalized] else { continue }
                        while placed < required, let index = windows.firstIndex(where: {
                            $0.mode == task.mode && $0.minutes >= task.blockMinutes
                        }) {
                            let slot = windows.remove(at: index)
                            blocks.append(ProposedWorkBlock(taskID: task.id, date: normalized,
                                                            period: slot.period, mode: task.mode,
                                                            minutes: task.blockMinutes))
                            placed += 1
                        }
                        remaining[normalized] = windows
                    }
                }
                allocate(preferred); allocate(fallback)
                if placed < required, let logical = task.blocks.first {
                    for _ in placed..<required {
                        unscheduled.append(UnscheduledBlock(task: task, block: logical,
                                                            deadline: window.latestEligibleDate,
                                                            reason: .capacity))
                    }
                }
                if usesCriticalFlex { removeUnusedCriticalFlex(from: &remaining) }
                continue
            }
            var upperDate = window.latestEligibleDate
            var upperPeriod = Int.max
            for sourceBlock in task.blocks.sorted(by: { $0.orderIndex > $1.orderIndex }) {
                let blockLocks = lockedBlocks.filter {
                    $0.taskID == task.id && $0.blockDefinitionID == sourceBlock.id
                }
                let lockedMinutes = blockLocks.reduce(0) { $0 + $1.estimatedMinutes }
                let remainingMinutes = max(0, sourceBlock.remainingMinutes - lockedMinutes)
                let lockedStart = blockLocks.min {
                    ($0.date, $0.period.planningOrder) < ($1.date, $1.period.planningOrder)
                }
                let isFirstBlock = sourceBlock.orderIndex == task.blocks.map(\.orderIndex).min()
                let manualDate = task.manualStartBy.map { calendar.startOfDay(for: $0) }
                let lockedSatisfiesStart = isFirstBlock && blockLocks.contains {
                    guard let manualDate else { return false }
                    return calendar.startOfDay(for: $0.date) <= manualDate
                }
                // A missed Start By is a historical checkpoint, not a reason to reject all
                // future catch-up work. Keep the user's override visible, but schedule the
                // first unfinished block immediately from today's remaining capacity.
                let actionableManualDate = manualDate.flatMap { $0 >= today ? $0 : nil }
                let startConstraint = isFirstBlock && !lockedSatisfiesStart ? actionableManualDate : nil
                if remainingMinutes == 0 {
                    if let lockedStart {
                        upperDate = calendar.startOfDay(for: lockedStart.date)
                        upperPeriod = lockedStart.period.planningOrder
                    }
                    continue
                }
                let logicalBlock = PlannerBlockInput(
                    id: sourceBlock.id, orderIndex: sourceBlock.orderIndex, title: sourceBlock.title,
                    remainingMinutes: remainingMinutes, estimatedMinutes: sourceBlock.estimatedMinutes,
                    splittable: sourceBlock.splittable,
                    minimumSessionMinutes: sourceBlock.minimumSessionMinutes
                )
                let candidates = availableSlots(remaining: remaining, mode: task.mode,
                                                through: upperDate, upperPeriod: upperPeriod,
                                                minimumMinutes: logicalBlock.minimumSessionMinutes)
                guard let selected = selectSlots(for: logicalBlock, from: candidates,
                                                 startBy: startConstraint) else {
                    let hasBeforeStart = startConstraint.map { requiredStart in
                        candidates.contains { $0.date <= requiredStart }
                    } ?? true
                    let reason: ScheduleConflictReason
                    if !hasBeforeStart { reason = .manualStartBy }
                    else if !logicalBlock.splittable { reason = .nonSplittableBlock }
                    else {
                        let raw = availableSlots(remaining: remaining, mode: task.mode,
                                                 through: upperDate, upperPeriod: upperPeriod,
                                                 minimumMinutes: 1)
                        reason = raw.reduce(0, { $0 + $1.window.minutes }) >= logicalBlock.remainingMinutes
                            ? .minimumSession : .capacity
                    }
                    unscheduled.append(UnscheduledBlock(task: task, block: logicalBlock,
                                                        deadline: startConstraint ?? window.latestEligibleDate,
                                                        reason: reason))
                    continue
                }
                let allocations = allocateMinutes(logicalBlock.remainingMinutes, across: selected,
                                                  minimum: logicalBlock.minimumSessionMinutes)
                remove(selected, from: &remaining)
                for (sessionIndex, item) in zip(selected.sorted(by: slotOrder), allocations).enumerated() {
                    blocks.append(ProposedWorkBlock(taskID: task.id, date: item.0.date,
                                                    period: item.0.window.period, mode: task.mode,
                                                    minutes: item.1, blockDefinitionID: logicalBlock.id,
                                                    sessionOrderIndex: sessionIndex))
                }
                let earliestSelected = selected.min(by: slotOrder).map {
                    ($0.date, $0.window.period.planningOrder)
                }
                let earliestLocked = lockedStart.map {
                    (calendar.startOfDay(for: $0.date), $0.period.planningOrder)
                }
                if let earliest = [earliestSelected, earliestLocked].compactMap({ $0 }).min(by: {
                    ($0.0, $0.1) < ($1.0, $1.1)
                }) {
                    upperDate = earliest.0
                    upperPeriod = earliest.1
                }
            }
            if usesCriticalFlex { removeUnusedCriticalFlex(from: &remaining) }
        }

        let latestSafeStarts = Dictionary(grouping: blocks, by: \.taskID).mapValues { $0.map(\.date).min() }
        optimizeForwardForComfort(&blocks, remaining: &remaining, capacities: capacities,
                                  capacityByDay: capacityByDay, taskByID: taskByID,
                                  targetDates: latestEligibleDates, calendar: calendar)

        let allPlannedDates = Dictionary(grouping: blocks, by: \.taskID).mapValues { $0.map(\.date) }
        let lockedDates = Dictionary(grouping: lockedBlocks, by: \.taskID).mapValues { $0.map(\.date) }
        let ranks = executionRanks(active, plannedDates: allPlannedDates, targetDates: latestEligibleDates,
                                   today: today, taskByID: taskByID,
                                   effectivePriorityTiers: effectivePriorityTiers)
        var metadata: [UUID: TaskPlanMetadata] = [:]
        for task in active {
            let dates = (allPlannedDates[task.id] ?? []) + (lockedDates[task.id] ?? [])
            let start = dates.min()
            let target = preferredDates[task.id]
            metadata[task.id] = TaskPlanMetadata(
                startBy: task.manualStartBy == nil
                    ? (latestSafeStarts[task.id] ?? start ?? target)
                    : (task.recommendedStartBy ?? target),
                plannedStart: start,
                executionRank: ranks.firstIndex(of: task.id).map { $0 + 1 } ?? active.count,
                reason: reason(for: task, start: start, target: target, taskByID: taskByID)
            )
        }

        let conflicts = Dictionary(grouping: unscheduled, by: { "\($0.task.mode.rawValue)|\($0.deadline.timeIntervalSince1970)|\($0.reason.rawValue)" })
            .compactMap { _, entries -> ScheduleConflict? in
                guard let first = entries.first else { return nil }
                let affectedIDs = Set(entries.map(\.task.id))
                let affectedTasks = active.filter { affectedIDs.contains($0.id) }
                let missing = entries.count
                let required = affectedTasks.reduce(0) { $0 + $1.remainingBlocks }
                return ScheduleConflict(mode: first.task.mode, deadline: first.deadline,
                                        required: required,
                                        available: max(0, required - missing),
                                        taskIDs: affectedTasks.map(\.id),
                                        taskTitles: affectedTasks.map(\.title), reason: first.reason,
                                        blockDefinitionID: entries.count == 1 ? first.block.id : nil)
            }
            .sorted { $0.deadline < $1.deadline }

        return PlannerOutput(blocks: blocks.sorted(by: blockOrder), taskMetadata: metadata, conflicts: conflicts)
    }

    private static func availableSlots(remaining: [Date: [CapacityWindow]], mode: WorkMode,
                                       through upperDate: Date, upperPeriod: Int,
                                       minimumMinutes: Int) -> [AvailableSlot] {
        remaining.flatMap { date, windows in
            windows.enumerated().compactMap { index, window in
                guard window.mode == mode, window.minutes >= minimumMinutes,
                      date < upperDate || (date == upperDate && window.period.planningOrder <= upperPeriod)
                else { return nil }
                return AvailableSlot(date: date, index: index, window: window)
            }
        }.sorted(by: slotOrder)
    }

    private static func selectSlots(for block: PlannerBlockInput, from candidates: [AvailableSlot],
                                    startBy: Date?) -> [AvailableSlot]? {
        guard block.remainingMinutes > 0 else { return [] }
        let permittedSingle = candidates.filter { slot in
            slot.window.minutes >= block.remainingMinutes && (startBy == nil || slot.date <= startBy!)
        }
        if let single = permittedSingle.last { return [single] }
        guard block.splittable else { return nil }
        let maximumSessions = min(candidates.count, max(2, block.remainingMinutes / max(1, block.minimumSessionMinutes)))
        guard maximumSessions >= 2 else { return nil }
        for count in 2...maximumSessions {
            guard block.remainingMinutes >= count * block.minimumSessionMinutes else { continue }
            var selected = Array(candidates.sorted {
                if $0.window.minutes != $1.window.minutes { return $0.window.minutes > $1.window.minutes }
                return slotOrder($1, $0)
            }.prefix(count))
            if let startBy, !selected.contains(where: { $0.date <= startBy }) {
                for early in candidates.filter({ $0.date <= startBy }).reversed() {
                    var replacement = selected
                    replacement[replacement.count - 1] = early
                    selected = Array(SetSlot.deduplicated(replacement))
                    if selected.count == count { break }
                }
            }
            guard selected.count == count,
                  startBy == nil || selected.contains(where: { $0.date <= startBy! }),
                  selected.reduce(0, { $0 + $1.window.minutes }) >= block.remainingMinutes
            else { continue }
            return selected.sorted(by: slotOrder)
        }
        return nil
    }

    private enum SetSlot {
        static func deduplicated(_ slots: [AvailableSlot]) -> [AvailableSlot] {
            var seen = Set<String>()
            return slots.filter { seen.insert("\($0.date.timeIntervalSince1970)|\($0.index)").inserted }
        }
    }

    private static func allocateMinutes(_ total: Int, across slots: [AvailableSlot], minimum: Int) -> [Int] {
        var values = Array(repeating: minimum, count: slots.count)
        var remaining = total - minimum * slots.count
        for index in slots.indices.reversed() where remaining > 0 {
            let addition = min(remaining, slots[index].window.minutes - minimum)
            values[index] += addition; remaining -= addition
        }
        return values
    }

    private static func remove(_ slots: [AvailableSlot], from remaining: inout [Date: [CapacityWindow]]) {
        for (date, items) in Dictionary(grouping: slots, by: \.date) {
            var windows = remaining[date] ?? []
            for index in items.map(\.index).sorted(by: >) where windows.indices.contains(index) {
                windows.remove(at: index)
            }
            remaining[date] = windows
        }
    }

    private static func slotOrder(_ left: AvailableSlot, _ right: AvailableSlot) -> Bool {
        if left.date != right.date { return left.date < right.date }
        return left.window.period.planningOrder < right.window.period.planningOrder
    }

    private static func effectiveSchedulingWindows(
        _ tasks: [PlannerTaskInput], taskByID: [UUID: PlannerTaskInput], today: Date, calendar: Calendar
    ) -> [UUID: TaskSchedulingWindow] {
        var result: [UUID: TaskSchedulingWindow] = [:]
        for task in tasks {
            let raw = [task.deadline, task.meetingDate].compactMap { $0 }.min()
                ?? calendar.date(byAdding: .day, value: 21, to: today) ?? today
            var buffer = task.deadlineType == .hard ? 1 : 0
            if task.uncertainty == .high { buffer += 1 }
            let latestEligibleDate = calendar.startOfDay(for: raw)
            let preferredFinishDate = calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: -buffer, to: latestEligibleDate) ?? latestEligibleDate
            )
            result[task.id] = TaskSchedulingWindow(preferredFinishDate: preferredFinishDate,
                                                   latestEligibleDate: latestEligibleDate)
        }
        // A prerequisite must be ready before the dependent task's safe start window.
        for _ in tasks.indices {
            var changed = false
            for task in tasks {
                guard let dependentWindow = result[task.id] else { continue }
                let prerequisiteTarget = calendar.date(byAdding: .day, value: -1,
                                                       to: dependentWindow.preferredFinishDate)
                    ?? dependentWindow.preferredFinishDate
                for dependency in task.dependencies where taskByID[dependency] != nil {
                    guard var prerequisiteWindow = result[dependency] else { continue }
                    if prerequisiteWindow.latestEligibleDate > prerequisiteTarget {
                        prerequisiteWindow.latestEligibleDate = prerequisiteTarget
                        prerequisiteWindow.preferredFinishDate = min(prerequisiteWindow.preferredFinishDate,
                                                                     prerequisiteTarget)
                        result[dependency] = prerequisiteWindow
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return result
    }

    private static func rejectCycles(in tasks: [PlannerTaskInput]) throws {
        let ids = Set(tasks.map(\.id))
        let edges = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.dependencies.filter(ids.contains)) })
        var visiting = Set<UUID>()
        var visited = Set<UUID>()
        var path: [UUID] = []
        func visit(_ id: UUID) -> [UUID]? {
            if visiting.contains(id), let start = path.firstIndex(of: id) { return Array(path[start...]) + [id] }
            if visited.contains(id) { return nil }
            visiting.insert(id); path.append(id)
            for next in edges[id] ?? [] { if let cycle = visit(next) { return cycle } }
            _ = path.popLast(); visiting.remove(id); visited.insert(id)
            return nil
        }
        for id in ids { if let cycle = visit(id) { throw PlannerError.dependencyCycle(cycle) } }
    }

    private static func effectivePriorityTiers(_ tasks: [PlannerTaskInput]) -> [UUID: Int] {
        let ids = Set(tasks.map(\.id))
        var tiers = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.priority.schedulingTier) })
        // Prerequisites inherit the strongest tier of work they unblock so that a
        // lower-labelled prerequisite cannot consume capacity too late for a Critical chain.
        for _ in tasks.indices {
            var changed = false
            for task in tasks {
                let dependentTier = tiers[task.id] ?? task.priority.schedulingTier
                for dependency in task.dependencies where ids.contains(dependency) {
                    if dependentTier < (tiers[dependency] ?? Int.max) {
                        tiers[dependency] = dependentTier
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return tiers
    }

    private static func topologicallyOrdered(_ tasks: [PlannerTaskInput], targetDates: [UUID: Date],
                                             effectivePriorityTiers: [UUID: Int]) -> [PlannerTaskInput] {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var visited = Set<UUID>(); var result: [PlannerTaskInput] = []
        func visit(_ task: PlannerTaskInput) {
            guard !visited.contains(task.id) else { return }
            visited.insert(task.id)
            for id in task.dependencies { if let prerequisite = byID[id] { visit(prerequisite) } }
            result.append(task)
        }
        for task in tasks.sorted(by: {
            let leftTier = effectivePriorityTiers[$0.id] ?? $0.priority.schedulingTier
            let rightTier = effectivePriorityTiers[$1.id] ?? $1.priority.schedulingTier
            if leftTier != rightTier { return leftTier < rightTier }
            let left = targetDates[$0.id] ?? .distantFuture, right = targetDates[$1.id] ?? .distantFuture
            if left != right { return left < right }
            return $0.remainingBlocks > $1.remainingBlocks
        }) { visit(task) }
        return result
    }

    private static func executionRanks(
        _ tasks: [PlannerTaskInput], plannedDates: [UUID: [Date]], targetDates: [UUID: Date],
        today: Date, taskByID: [UUID: PlannerTaskInput], effectivePriorityTiers: [UUID: Int]
    ) -> [UUID] {
        let blocking = Set(tasks.flatMap(\.dependencies))
        return tasks.sorted { left, right in
            let leftTier = effectivePriorityTiers[left.id] ?? left.priority.schedulingTier
            let rightTier = effectivePriorityTiers[right.id] ?? right.priority.schedulingTier
            if leftTier != rightTier { return leftTier < rightTier }
            let leftToday = plannedDates[left.id]?.contains(today) ?? false
            let rightToday = plannedDates[right.id]?.contains(today) ?? false
            if leftToday != rightToday { return leftToday }
            if blocking.contains(left.id) != blocking.contains(right.id) { return blocking.contains(left.id) }
            let leftSlack = (targetDates[left.id] ?? .distantFuture).timeIntervalSince(today) / 86_400 - Double(left.remainingBlocks)
            let rightSlack = (targetDates[right.id] ?? .distantFuture).timeIntervalSince(today) / 86_400 - Double(right.remainingBlocks)
            if leftSlack != rightSlack { return leftSlack < rightSlack }
            let leftRisk = left.size == .extraLarge || left.uncertainty == .high
            let rightRisk = right.size == .extraLarge || right.uncertainty == .high
            if leftRisk != rightRisk { return leftRisk }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }.map(\.id)
    }

    private static func optimizeForwardForComfort(
        _ blocks: inout [ProposedWorkBlock], remaining: inout [Date: [CapacityWindow]],
        capacities: [PlannerCapacityDay], capacityByDay: [Date: PlannerCapacityDay],
        taskByID: [UUID: PlannerTaskInput], targetDates: [UUID: Date], calendar: Calendar
    ) {
        let today = capacities.first.map { calendar.startOfDay(for: $0.date) } ?? .distantPast
        let sessionCount = Dictionary(grouping: blocks, by: \.taskID).mapValues(\.count)
        let logicalOrder: [UUID: [UUID: Int]] = taskByID.mapValues { task in
            Dictionary(uniqueKeysWithValues: task.blocks.map { ($0.id, $0.orderIndex) })
        }
        let indices = blocks.indices.sorted { lhs, rhs in
            let left = blocks[lhs], right = blocks[rhs]
            if left.taskID != right.taskID {
                let leftTier = taskByID[left.taskID]?.priority.schedulingTier ?? Int.max
                let rightTier = taskByID[right.taskID]?.priority.schedulingTier ?? Int.max
                if leftTier != rightTier { return leftTier < rightTier }
                return left.taskID.uuidString < right.taskID.uuidString
            }
            let leftOrder = left.blockDefinitionID.flatMap { logicalOrder[left.taskID]?[$0] } ?? 0
            let rightOrder = right.blockDefinitionID.flatMap { logicalOrder[right.taskID]?[$0] } ?? 0
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return left.sessionOrderIndex < right.sessionOrderIndex
        }
        var previousPlacement: [UUID: (date: Date, period: Int)] = [:]
        var taskDays: [UUID: Set<Date>] = [:]

        for index in indices {
            let block = blocks[index]
            let current = calendar.startOfDay(for: block.date)
            guard let task = taskByID[block.taskID], block.mode == .deep else {
                previousPlacement[block.taskID] = (current, block.period.planningOrder)
                taskDays[block.taskID, default: []].insert(current)
                continue
            }
            let currentKind = capacityByDay[current]?.kind
            let spreadsCriticalWork = task.priority == .critical && (sessionCount[task.id] ?? 0) > 1
            guard currentKind == .school || spreadsCriticalWork else {
                previousPlacement[task.id] = (current, block.period.planningOrder)
                taskDays[task.id, default: []].insert(current)
                continue
            }
            let target = targetDates[task.id] ?? current
            let lower = previousPlacement[task.id]
            let open = remaining.flatMap { date, windows in
                windows.enumerated().compactMap { offset, window -> AvailableSlot? in
                    let day = calendar.startOfDay(for: date)
                    guard day >= today, day <= target, day < current,
                          capacityByDay[day]?.kind == .free,
                          window.mode == block.mode, window.minutes >= block.minutes
                    else { return nil }
                    if let lower, (day, window.period.planningOrder) <= (lower.date, lower.period) { return nil }
                    return AvailableSlot(date: day, index: offset, window: window)
                }
            }
            let unusedDay = open.filter { !(taskDays[task.id] ?? []).contains($0.date) }
            guard let better = (unusedDay.isEmpty ? open : unusedDay).sorted(by: slotOrder).first else {
                previousPlacement[task.id] = (current, block.period.planningOrder)
                taskDays[task.id, default: []].insert(current)
                continue
            }

            if var windows = remaining[better.date], windows.indices.contains(better.index) {
                windows.remove(at: better.index)
                remaining[better.date] = windows
            }
            let restored = capacityByDay[current].flatMap { day in
                capacityWindows(for: day).first { $0.mode == block.mode && $0.period == block.period }
            } ?? CapacityWindow(mode: block.mode, period: block.period, minutes: block.minutes)
            remaining[current, default: []].append(restored)
            blocks[index].date = better.date
            blocks[index].period = better.window.period
            previousPlacement[task.id] = (better.date, better.window.period.planningOrder)
            taskDays[task.id, default: []].insert(better.date)
        }
    }

    private static func reason(for task: PlannerTaskInput, start: Date?, target: Date?, taskByID: [UUID: PlannerTaskInput]) -> String {
        var parts: [String] = []
        if task.deadlineType == .hard { parts.append("A safety buffer is reserved before the hard deadline") }
        if task.uncertainty == .high { parts.append("extra room is included for uncertainty") }
        if !task.dependencies.isEmpty { parts.append("prerequisite work is scheduled before this task") }
        if task.meetingDate != nil { parts.append("required work is placed before the related meeting") }
        if task.mode == .deep { parts.append("deep work is placed in the highest-quality available blocks") }
        if parts.isEmpty { parts.append("work is spread across available capacity without filling every hour") }
        return parts.joined(separator: "; ").capitalized + "."
    }

    private static func dayCapacity(_ day: PlannerCapacityDay, mode: WorkMode) -> Int {
        switch mode { case .deep: day.deep; case .medium: day.medium; case .fragmentable: day.fragment }
    }

    private static func period(for mode: WorkMode, day: PlannerCapacityDay, ordinal: Int) -> WorkBlockPeriod {
        switch mode {
        case .deep:
            if day.preferredDeepPeriods.indices.contains(ordinal) { return day.preferredDeepPeriods[ordinal] }
            return day.kind == .free ? (ordinal == 0 ? .deep1 : .deep2) : .evening
        case .medium: return day.kind == .school ? .evening : .afternoon
        case .fragmentable: return day.kind == .school ? .schoolFragment : .flexible
        }
    }

    private static func capacityWindows(for day: PlannerCapacityDay) -> [CapacityWindow] {
        func make(_ mode: WorkMode, _ minutes: [Int]) -> [CapacityWindow] {
            minutes.enumerated().map { ordinal, duration in
                CapacityWindow(mode: mode, period: period(for: mode, day: day, ordinal: ordinal),
                               minutes: max(1, duration))
            }
        }
        return make(.deep, day.deepPeriodMinutes)
            + make(.medium, day.mediumPeriodMinutes)
            + make(.fragmentable, day.fragmentPeriodMinutes)
    }

    /// Critical work with a fixed official deadline may use a free day's reserve
    /// capacity after the normal cognitive budget is exhausted. These remain Deep
    /// sessions, are limited to two additional daytime periods, and are scoped to
    /// the critical task currently being scheduled so lower-priority work cannot
    /// consume the emergency reserve.
    private static func addCriticalFreeDayFlex(
        to remaining: inout [Date: [CapacityWindow]],
        capacities: [PlannerCapacityDay],
        through deadline: Date,
        calendar: Calendar
    ) {
        for day in capacities where day.kind == .free && day.date <= deadline {
            let normalized = calendar.startOfDay(for: day.date)
            remaining[normalized, default: []].append(contentsOf: [
                CapacityWindow(mode: .deep, period: .morning, minutes: 120, isCriticalFlex: true),
                CapacityWindow(mode: .deep, period: .afternoon, minutes: 120, isCriticalFlex: true)
            ])
        }
    }

    private static func removeUnusedCriticalFlex(from remaining: inout [Date: [CapacityWindow]]) {
        for date in remaining.keys {
            remaining[date]?.removeAll(where: \.isCriticalFlex)
        }
    }

    private static func blockOrder(_ left: ProposedWorkBlock, _ right: ProposedWorkBlock) -> Bool {
        if left.date != right.date { return left.date < right.date }
        if left.period.planningOrder != right.period.planningOrder {
            return left.period.planningOrder < right.period.planningOrder
        }
        return left.sessionOrderIndex < right.sessionOrderIndex
    }
}
