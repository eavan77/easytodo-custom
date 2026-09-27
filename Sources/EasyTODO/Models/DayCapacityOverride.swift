import Foundation
import SwiftData

@Model
final class DayCapacityOverride {
    var id: UUID = UUID()
    var date: Date
    var additionalDeepCapacity: Int
    var additionalMediumCapacity: Int
    var additionalFragmentCapacity: Int
    var reason: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        additionalDeepCapacity: Int = 0,
        additionalMediumCapacity: Int = 0,
        additionalFragmentCapacity: Int = 0,
        reason: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.additionalDeepCapacity = additionalDeepCapacity
        self.additionalMediumCapacity = additionalMediumCapacity
        self.additionalFragmentCapacity = additionalFragmentCapacity
        self.reason = reason
        self.createdAt = createdAt
    }
}
