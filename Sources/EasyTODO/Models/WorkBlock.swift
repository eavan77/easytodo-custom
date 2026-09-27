import Foundation
import SwiftData

@Model
final class WorkBlock {
    var id: UUID = UUID()
    var taskID: UUID
    var date: Date
    var periodRawValue: String
    var modeRawValue: String
    var estimatedMinutes: Int
    var statusRawValue: String
    var locked: Bool
    var actualMinutes: Int?
    var notes: String
    var splitGroupID: UUID?
    var taskBlockDefinitionID: UUID?
    var sessionOrderIndex: Int?

    init(
        id: UUID = UUID(),
        taskID: UUID,
        date: Date,
        period: WorkBlockPeriod,
        mode: WorkMode,
        estimatedMinutes: Int,
        status: WorkBlockStatus = .planned,
        locked: Bool = false,
        actualMinutes: Int? = nil,
        notes: String = "",
        splitGroupID: UUID? = nil,
        taskBlockDefinitionID: UUID? = nil,
        sessionOrderIndex: Int? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.date = Calendar.current.startOfDay(for: date)
        self.periodRawValue = period.rawValue
        self.modeRawValue = mode.rawValue
        self.estimatedMinutes = estimatedMinutes
        self.statusRawValue = status.rawValue
        self.locked = locked
        self.actualMinutes = actualMinutes
        self.notes = notes
        self.splitGroupID = splitGroupID
        self.taskBlockDefinitionID = taskBlockDefinitionID
        self.sessionOrderIndex = sessionOrderIndex
    }

    var period: WorkBlockPeriod {
        get { WorkBlockPeriod(rawValue: periodRawValue) ?? .flexible }
        set { periodRawValue = newValue.rawValue }
    }

    var mode: WorkMode {
        get { WorkMode(rawValue: modeRawValue) ?? .medium }
        set { modeRawValue = newValue.rawValue }
    }

    var status: WorkBlockStatus {
        get { WorkBlockStatus(rawValue: statusRawValue) ?? .planned }
        set { statusRawValue = newValue.rawValue }
    }
}
