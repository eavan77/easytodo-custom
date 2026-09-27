import Foundation

enum WorkBlockNumbering {
    static func displayNumber(for block: WorkBlock, task: TodoTask, among blocks: [WorkBlock]) -> Int {
        let remaining = blocks
            .filter { candidate in
                candidate.taskID == task.id && candidate.status != .done && candidate.status != .skipped
            }
            .sorted(by: scheduledOrder)
        let index = remaining.firstIndex { $0.id == block.id } ?? 0
        return task.safeCompletedBlocks + index + 1
    }

    private static func scheduledOrder(_ left: WorkBlock, _ right: WorkBlock) -> Bool {
        if left.date != right.date { return left.date < right.date }
        if left.period.planningOrder != right.period.planningOrder {
            return left.period.planningOrder < right.period.planningOrder
        }
        return left.id.uuidString < right.id.uuidString
    }
}
