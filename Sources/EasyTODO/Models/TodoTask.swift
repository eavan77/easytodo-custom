import Foundation
import SwiftData

@Model
final class TodoTask {
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: Date
    var scheduledDate: Date?
    var hasExplicitDueTime: Bool = false
    var completedAt: Date?
    var category: TaskCategory?
    var priorityRawValue: String?
    var repeatRuleRawValue: String?
    var recurrenceGroupID: String?

    init(
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        scheduledDate: Date? = nil,
        hasExplicitDueTime: Bool = false,
        completedAt: Date? = nil,
        category: TaskCategory? = nil,
        priority: TaskPriority = .notUrgentImportant,
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
        self.priorityRawValue = priority.rawValue
        self.repeatRuleRawValue = repeatRule.rawValue
        self.recurrenceGroupID = recurrenceGroupID
    }

    var priority: TaskPriority {
        get {
            TaskPriority.normalized(from: priorityRawValue)
        }
        set {
            priorityRawValue = newValue.rawValue
        }
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
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(scheduledDay(in: calendar), inSameDayAs: date)
    }
}
