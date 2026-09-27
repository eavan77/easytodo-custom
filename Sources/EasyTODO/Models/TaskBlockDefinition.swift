import Foundation
import SwiftData

enum TaskBlockStatus: String, CaseIterable, Codable {
    case planned
    case inProgress
    case done
}

@Model
final class TaskBlockDefinition {
    var id: UUID = UUID()
    var taskID: UUID
    var orderIndex: Int
    var title: String
    var estimatedMinutes: Int?
    var splittable: Bool
    var minimumSessionMinutes: Int?
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), taskID: UUID, orderIndex: Int, title: String,
         estimatedMinutes: Int? = nil, splittable: Bool = true,
         minimumSessionMinutes: Int? = nil, status: TaskBlockStatus = .planned,
         createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.taskID = taskID; self.orderIndex = orderIndex; self.title = title
        self.estimatedMinutes = estimatedMinutes.map { max(1, $0) }
        self.splittable = splittable
        self.minimumSessionMinutes = minimumSessionMinutes.map { max(1, $0) }
        self.statusRawValue = status.rawValue; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    var status: TaskBlockStatus {
        get { TaskBlockStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue; updatedAt = .now }
    }

    func effectiveMinutes(taskDefault: Int) -> Int { max(1, estimatedMinutes ?? taskDefault) }

    func refreshStatus(sessions: [WorkBlock], taskDefaultMinutes: Int) {
        let related = sessions.filter { $0.taskBlockDefinitionID == id && $0.status != .skipped }
        let doneMinutes = related.filter { $0.status == .done }.reduce(0) { $0 + $1.estimatedMinutes }
        let required = effectiveMinutes(taskDefault: taskDefaultMinutes)
        if doneMinutes >= required { status = .done }
        else if doneMinutes > 0 { status = .inProgress }
        else { status = .planned }
    }
}
