import Foundation

enum TaskListOrdering {
    static func ordered(_ tasks: [TodoTask]) -> [TodoTask] {
        let active = TaskUrgencyOrdering.ordered(tasks.filter { !$0.isCompleted })
        let completed = tasks.filter(\.isCompleted).sorted { lhs, rhs in
            switch (lhs.completedAt, rhs.completedAt) {
            case let (.some(left), .some(right)) where left != right: return left > right
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
        }
        return active + completed
    }

    static func moveCompletedTaskToFront(_ task: TodoTask, in tasks: [TodoTask]) {
        let activeTasks = ordered(tasks).filter { !$0.isCompleted && $0 !== task }
        let completedTasks = ordered(tasks).filter { $0.isCompleted && $0 !== task }

        renumber(activeTasks + [task] + completedTasks)
    }

    static func moveReactivatedTaskToEnd(_ task: TodoTask, in tasks: [TodoTask]) {
        let activeTasks = ordered(tasks).filter { !$0.isCompleted && $0 !== task }
        let completedTasks = ordered(tasks).filter { $0.isCompleted && $0 !== task }

        renumber(activeTasks + [task] + completedTasks)
    }

    static func moveTasks(from source: IndexSet, to destination: Int, in tasks: [TodoTask]) {
        var reorderedTasks = ordered(tasks)
        reorderedTasks.move(fromOffsets: source, toOffset: destination)

        let activeTasks = reorderedTasks.filter { !$0.isCompleted }
        let completedTasks = reorderedTasks.filter(\.isCompleted)

        renumber(activeTasks + completedTasks)
    }

    private static func renumber(_ tasks: [TodoTask]) {
        for (index, task) in tasks.enumerated() {
            task.sortOrder = index
        }
    }
}
