import Foundation
import SwiftData

@Model
final class TodoTask {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    var scheduledDate: Date?
    var hasExplicitDueTime: Bool = false
    var completedAt: Date?
    var category: TaskCategory?
    var priorityRawValue: String?
    var planningPriorityRawValue: String?
    var prioritySourceRawValue: String?
    var repeatRuleRawValue: String?
    var recurrenceGroupID: String?
    var deadlineTypeRawValue: String?
    var deadlineTypeSourceRawValue: String?
    var workModeRawValue: String?
    var sizeRawValue: String?
    var energyDemandRawValue: String?
    var estimatedMinutes: Int?
    var estimatedBlocks: Int?
    var splittable: Bool?
    var minimumBlockMinutes: Int?
    var uncertaintyRawValue: String?
    var startBy: Date?
    var manualStartBy: Date?
    var plannedStart: Date?
    var executionRank: Int?
    var progress: Double?
    var completedBlocks: Int?
    var dependencyIDsRawValue: String?
    var blockedByRawValue: String?
    var relatedMeetingDate: Date?
    var plannerLocked: Bool?
    var manualPriority: Int?
    var plannerReason: String?
    var aiConfidence: Double?
    var notes: String?

    init(
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        scheduledDate: Date? = nil,
        hasExplicitDueTime: Bool = false,
        completedAt: Date? = nil,
        category: TaskCategory? = nil,
        colorPriority: TaskColorPriority = .notUrgentImportant,
        repeatRule: TaskRepeatRule = .none,
        recurrenceGroupID: String? = nil
    ) {
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.scheduledDate = scheduledDate.map {
            hasExplicitDueTime ? $0 : Calendar.current.startOfDay(for: $0)
        }
        self.hasExplicitDueTime = scheduledDate != nil && hasExplicitDueTime
        self.completedAt = completedAt
        self.category = category
        self.priorityRawValue = colorPriority.rawValue
        self.repeatRuleRawValue = repeatRule.rawValue
        self.recurrenceGroupID = recurrenceGroupID
    }

    var deadlineType: DeadlineType {
        get { DeadlineType(rawValue: deadlineTypeRawValue ?? "") ?? (scheduledDate == nil ? .none : .hard) }
        set { deadlineTypeRawValue = newValue.rawValue }
    }

    var explicitDeadlineType: DeadlineType? {
        guard let deadlineTypeRawValue else { return nil }
        return DeadlineType(rawValue: deadlineTypeRawValue)
    }

    var deadlineTypeWasExplicitlySet: Bool { explicitDeadlineType != nil }

    var deadlineTypeSource: DeadlineTypeSource {
        get {
            if let value = deadlineTypeSourceRawValue.flatMap(DeadlineTypeSource.init(rawValue:)) { return value }
            if deadlineTypeRawValue == nil, scheduledDate != nil { return .legacyFallback }
            // Legacy fallback never wrote a raw value. A pre-source raw value was
            // therefore chosen through the deadline-type UI and remains authoritative.
            return deadlineTypeRawValue == nil ? .unknown : .userSelected
        }
        set { deadlineTypeSourceRawValue = newValue.rawValue }
    }

    func setDeadlineType(_ type: DeadlineType, source: DeadlineTypeSource) {
        deadlineType = type
        deadlineTypeSource = source
    }

    var workMode: WorkMode {
        get { WorkMode(rawValue: workModeRawValue ?? "") ?? .medium }
        set { workModeRawValue = newValue.rawValue }
    }

    var taskSize: TaskSize {
        get { TaskSize(rawValue: sizeRawValue ?? "") ?? .medium }
        set { sizeRawValue = newValue.rawValue }
    }

    var energyDemand: EnergyDemand {
        get { EnergyDemand(rawValue: energyDemandRawValue ?? "") ?? .medium }
        set { energyDemandRawValue = newValue.rawValue }
    }

    var uncertainty: PlanningUncertainty {
        get { PlanningUncertainty(rawValue: uncertaintyRawValue ?? "") ?? .medium }
        set { uncertaintyRawValue = newValue.rawValue }
    }

    var dependencyIDs: [UUID] {
        get { Self.decodeIDs(dependencyIDsRawValue) }
        set { dependencyIDsRawValue = newValue.map(\.uuidString).joined(separator: ",") }
    }

    var blockedBy: [UUID] {
        get { Self.decodeIDs(blockedByRawValue) }
        set { blockedByRawValue = newValue.map(\.uuidString).joined(separator: ",") }
    }

    var safeEstimatedBlocks: Int { max(1, estimatedBlocks ?? Self.defaultBlocks(for: taskSize)) }
    var safeCompletedBlocks: Int { max(0, completedBlocks ?? 0) }
    var remainingBlocks: Int { max(0, safeEstimatedBlocks - safeCompletedBlocks) }
    var plannedBlockMinutes: Int {
        let minimum = max(15, minimumBlockMinutes ?? 15)
        guard let estimatedMinutes, estimatedMinutes > 0 else { return max(60, minimum) }
        return max(minimum, Int(ceil(Double(estimatedMinutes) / Double(safeEstimatedBlocks))))
    }
    var isPlannerLocked: Bool { plannerLocked ?? false }
    var recommendedStartBy: Date? { startBy }
    var effectiveStartBy: Date? { manualStartBy ?? startBy }
    var needsPlannerMetadata: Bool {
        sizeRawValue == nil || workModeRawValue == nil || estimatedBlocks == nil
            || energyDemandRawValue == nil || uncertaintyRawValue == nil || splittable == nil
    }

    func setPlanningEstimate(workMode: WorkMode, size: TaskSize, estimatedBlocks: Int,
                             energy: EnergyDemand, uncertainty: PlanningUncertainty,
                             splittable: Bool, blockMinutes: Int? = nil,
                             minimumBlockMinutes: Int? = nil) {
        self.workMode = workMode
        taskSize = size
        self.estimatedBlocks = max(1, estimatedBlocks)
        energyDemand = energy
        self.uncertainty = uncertainty
        self.splittable = splittable
        estimatedMinutes = blockMinutes.map { max(1, $0) * max(1, estimatedBlocks) }
        self.minimumBlockMinutes = minimumBlockMinutes.map { max(1, $0) }
    }

    func userSelectDeadlineType(_ type: DeadlineType) {
        setDeadlineType(type, source: .userSelected)
    }

    var deadlineSourceDescription: String {
        if deadlineTypeSource == .autoDetected,
           let match = FixedAssessmentRecognizer.match(in: title) {
            return "Auto-detected from “\(match.phrase)”"
        }
        return switch deadlineTypeSource {
        case .legacyFallback, .unknown: "Legacy / needs confirmation"
        default: deadlineTypeSource.title
        }
    }

    private static func decodeIDs(_ value: String?) -> [UUID] {
        (value ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    private static func defaultBlocks(for size: TaskSize) -> Int {
        switch size { case .small: 1; case .medium: 1; case .large: 2; case .extraLarge: 3 }
    }

    var colorPriority: TaskColorPriority {
        get {
            TaskColorPriority.normalized(from: priorityRawValue)
        }
        set {
            priorityRawValue = newValue.rawValue
        }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: planningPriorityRawValue ?? "") ?? .normal }
        set { planningPriorityRawValue = newValue.rawValue }
    }

    var prioritySource: PrioritySource {
        get { PrioritySource(rawValue: prioritySourceRawValue ?? "") ?? .default }
        set { prioritySourceRawValue = newValue.rawValue }
    }

    func userSelectPriority(_ priority: TaskPriority) {
        self.priority = priority
        prioritySource = .userSelected
    }

    var prioritySourceDescription: String {
        if prioritySource == .autoDetected,
           let match = FixedAssessmentRecognizer.match(in: title) {
            return "Auto-detected from “\(match.phrase)”"
        }
        return prioritySource.title
    }

    var repeatRule: TaskRepeatRule {
        get {
            TaskRepeatRule.normalized(from: repeatRuleRawValue)
        }
        set {
            repeatRuleRawValue = newValue.rawValue
        }
    }

    func scheduledDay(in calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: scheduledDate ?? .now)
    }

    func effectiveDeadline(in calendar: Calendar = .current) -> Date? {
        guard let scheduledDate else { return nil }
        if hasExplicitDueTime { return scheduledDate }
        let start = calendar.startOfDay(for: scheduledDate)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start)
    }

    func setDueDate(_ date: Date?, includesTime: Bool, calendar: Calendar = .current) {
        scheduledDate = date.map { includesTime ? $0 : calendar.startOfDay(for: $0) }
        hasExplicitDueTime = date != nil && includesTime
    }

    func setCompleted(_ completed: Bool, at date: Date = .now) {
        isCompleted = completed
        completedAt = completed ? date : nil
        NotificationCenter.default.post(name: .easyTODOPlanningInputsChanged, object: id)
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(scheduledDay(in: calendar), inSameDayAs: date)
    }
}
