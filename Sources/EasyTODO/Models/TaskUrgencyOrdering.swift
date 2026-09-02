import Foundation

enum TaskCategoryFilter: Equatable {
    case all
    case uncategorized
    case category(UUID)

    init(storedValue: String) {
        if storedValue == "uncategorized" { self = .uncategorized }
        else if let id = UUID(uuidString: storedValue) { self = .category(id) }
        else { self = .all }
    }
}

enum TaskUrgencyOrdering {
    static func visibleTasks(
        from tasks: [TodoTask],
        filter: TaskCategoryFilter = .all,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TodoTask] {
        ordered(
            tasks.filter { !$0.isCompleted && matches($0, filter: filter) },
            now: now,
            calendar: calendar
        )
    }

    static func ordered(
        _ tasks: [TodoTask],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TodoTask] {
        tasks.sorted { lhs, rhs in
            let leftDeadline = lhs.effectiveDeadline(in: calendar)
            let rightDeadline = rhs.effectiveDeadline(in: calendar)

            switch (leftDeadline, rightDeadline) {
            case let (.some(left), .some(right)):
                let leftOverdue = left < now
                let rightOverdue = right < now
                if leftOverdue != rightOverdue { return leftOverdue }
                if left != right { return left < right }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private static func matches(_ task: TodoTask, filter: TaskCategoryFilter) -> Bool {
        switch filter {
        case .all: true
        case .uncategorized: task.category == nil
        case let .category(id): task.category?.id == id
        }
    }
}
