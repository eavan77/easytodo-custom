import Foundation
import SwiftData

@Model
final class ScheduleConflictAcknowledgement {
    var conflictKey: String
    var createdAt: Date

    init(conflictKey: String, createdAt: Date = .now) {
        self.conflictKey = conflictKey
        self.createdAt = createdAt
    }
}
