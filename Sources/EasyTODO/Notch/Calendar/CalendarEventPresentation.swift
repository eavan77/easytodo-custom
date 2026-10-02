import Foundation

enum CalendarEventSource: Sendable, Equatable {
    case eventKit
    case easyTODO(UUID)
}

enum CalendarEventPresentation {
    static func snapshot(_ event: CalendarSpecialEvent) -> CalendarGlanceEvent {
        CalendarGlanceEvent(id: event.id, title: event.title, start: event.start,
                           end: event.end ?? event.start, isAllDay: event.isAllDay,
                           calendarTitle: "EasyTODO", source: .easyTODO(event.id),
                           categoryID: event.categoryID)
    }

    static func merged(local: [CalendarSpecialEvent], external: [CalendarGlanceEvent],
                       range: DateInterval) -> [CalendarGlanceEvent] {
        CalendarEventSnapshot(range: range, events: external + local.map(snapshot)).events(in: range)
    }

    static func category(for event: CalendarGlanceEvent, mappings: [String: UUID],
                         categories: [TaskCategory]) -> TaskCategory? {
        let id: UUID?
        switch event.source {
        case .easyTODO: id = event.categoryID
        case .eventKit: id = event.mappingKey.flatMap { mappings[$0] }
        }
        return categories.first { $0.id == id }
    }
}
