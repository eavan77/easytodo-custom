import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class CalendarEventProvider {
    enum State {
        case notDetermined
        case denied
        case restricted
        case writeOnly
        case loading
        case granted(CalendarEventSnapshot)
        case error(String)
    }

    private(set) var state: State = .notDetermined
    private let store = CalendarEventStore()
    private var refreshTask: Task<Void, Never>?
    private var revision = 0
    private var isRequestingAccess = false

    private var week = CalendarWeek(containing: .now, calendar: .current)

    func refresh(week: CalendarWeek? = nil) {
        if let week { self.week = week }
        guard !isRequestingAccess else { return }
        revision += 1
        let currentRevision = revision
        refreshTask?.cancel()

        guard updateAuthorizationState() else { return }
        state = .loading
        let range = self.week.interval
        refreshTask = Task {
            do {
                let glance = try await store.fetch(range: range)
                guard !Task.isCancelled, revision == currentRevision else { return }
                // Permission may have changed while the fetch was in flight.
                guard updateAuthorizationState() else { return }
                state = .granted(glance)
            } catch {
                guard !Task.isCancelled, revision == currentRevision else { return }
                state = .error(error.localizedDescription)
            }
        }
    }

    func requestAccess() async {
        guard !isRequestingAccess else { return }
        // swift run has no app Info.plist. Do not make an unsafe privacy request
        // from that executable; the packaging script supplies the real key.
        guard let description = Bundle.main.object(
            forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription"
        ) as? String, !description.isEmpty else {
            state = .error("Calendar permission requires the packaged EasyTODO.app. Build it with scripts/package_app.sh and open dist/EasyTODO.app.")
            return
        }

        isRequestingAccess = true
        revision += 1
        refreshTask?.cancel()
        state = .loading
        do {
            _ = try await store.requestAccess()
            isRequestingAccess = false
            refresh()
        } catch {
            isRequestingAccess = false
            state = .error(error.localizedDescription)
        }
    }

    private func updateAuthorizationState() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            state = .notDetermined
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .writeOnly:
            state = .writeOnly
        @unknown default:
            state = .error("This calendar access level is not supported.")
        }
        return false
    }
}

// EventKit objects stay in this actor. Only immutable value snapshots reach UI;
// synchronous event enumeration never blocks notch pointer handling/animation.
private actor CalendarEventStore {
    private let eventStore = EKEventStore()

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func fetch(range: DateInterval) throws -> CalendarEventSnapshot {
        try Task.checkCancellation()
        let predicate = eventStore.predicateForEvents(
            withStart: range.start,
            end: range.end,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate).map { event in
            CalendarGlanceEvent(
                id: UUID(),
                title: event.title?.isEmpty == false ? event.title : "Untitled event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                calendarIdentifier: event.calendar.calendarIdentifier,
                eventIdentifier: event.calendarItemIdentifier,
                occurrenceStart: event.occurrenceDate
            )
        }
        return CalendarEventSnapshot(range: range, events: events)
    }
}
