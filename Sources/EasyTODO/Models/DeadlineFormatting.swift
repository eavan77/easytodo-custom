import Foundation

enum DeadlineFormatting {
    static func text(for task: TodoTask, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let dueDate = task.scheduledDate else { return nil }
        let day: String
        if calendar.isDateInToday(dueDate) {
            day = "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            day = "Tomorrow"
        } else {
            day = dueDate.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }

        let isOverdue = (task.effectiveDeadline(in: calendar) ?? .distantFuture) < now
        let prefix = isOverdue ? "Overdue" : day
        guard task.hasExplicitDueTime else { return prefix }
        let time = dueDate.formatted(.dateTime.hour().minute().locale(locale))
        return "\(prefix) · \(time)"
    }
}
