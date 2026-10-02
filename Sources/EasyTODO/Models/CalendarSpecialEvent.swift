import Foundation
import SwiftData

@Model
final class CalendarSpecialEvent {
    @Attribute(.unique) var id: UUID
    var title: String
    var start: Date
    var end: Date?
    var isAllDay: Bool
    // Resolve against live TaskCategory records; a deleted category is neutral.
    var categoryID: UUID?

    init(title: String, start: Date, end: Date? = nil, isAllDay: Bool = false,
         categoryID: UUID? = nil, calendar: Calendar = .current) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ValidationError.emptyTitle }
        if !isAllDay, let end, end <= start { throw ValidationError.invalidEnd }
        self.id = UUID()
        self.title = title
        self.start = isAllDay ? calendar.startOfDay(for: start) : start
        self.end = isAllDay ? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) : end
        self.isAllDay = isAllDay
        self.categoryID = categoryID
    }

    enum ValidationError: LocalizedError {
        case emptyTitle, invalidEnd

        var errorDescription: String? {
            switch self {
            case .emptyTitle: "Enter an event title."
            case .invalidEnd: "End time must be later than the start time."
            }
        }
    }
}
