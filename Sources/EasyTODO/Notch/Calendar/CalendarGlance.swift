import Foundation

struct CalendarGlanceEvent: Identifiable, Sendable {
    // A snapshot ID also distinguishes recurring occurrences and duplicate imports.
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    var calendarIdentifier: String? = nil
    var eventIdentifier: String? = nil
    var occurrenceStart: Date? = nil
    var source: CalendarEventSource = .eventKit
    var categoryID: UUID? = nil

    // Stable within this EventKit store and occurrence. No title-based guesses.
    var mappingKey: String? {
        if case .easyTODO(let id) = source { return "local:\(id.uuidString)" }
        guard let calendarIdentifier, let eventIdentifier else { return nil }
        let occurrence = occurrenceStart.map { String($0.timeIntervalSinceReferenceDate) } ?? "single"
        return "\(calendarIdentifier.count):\(calendarIdentifier)\(eventIdentifier.count):\(eventIdentifier):\(occurrence)"
    }
}

struct CalendarEventSnapshot: Sendable {
    let range: DateInterval
    let events: [CalendarGlanceEvent]

    init(range: DateInterval, events: [CalendarGlanceEvent]) {
        self.range = range
        self.events = events.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func events(in day: DateInterval) -> [CalendarGlanceEvent] {
        events.filter {
            // EventKit end dates are exclusive. Keep overnight/multi-day events
            // in every day they overlap, and include zero-duration events once.
            $0.start < day.end && ($0.end > day.start || $0.start >= day.start)
        }
    }
}
