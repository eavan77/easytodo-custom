import Foundation
import Observation

enum CalendarSchoolDayHoverAction: Equatable {
    case markNoSchool
    case restoreSchoolCalendar
    case none

    var title: String {
        switch self {
        case .markNoSchool: "Mark as no school"
        case .restoreSchoolCalendar: "Restore school calendar"
        case .none: ""
        }
    }
}

@MainActor
@Observable
final class CalendarSchoolDayHover {
    private(set) var activeDate: Date?
    private var hoveredHeaderDate: Date?
    private var hoveredActionDate: Date?
    private var dismissalTask: Task<Void, Never>?
    private let dismissalDelay: Duration

    init(dismissalDelay: Duration = .milliseconds(180)) {
        self.dismissalDelay = dismissalDelay
    }

    static func action(baseStatus: SchoolDayStatus?, personalOverride: SchoolDayStatus?) -> CalendarSchoolDayHoverAction {
        switch baseStatus {
        case .regularSchoolDay, .replacementSchoolDay:
            return personalOverride == .noSchool ? .restoreSchoolCalendar : .markNoSchool
        case .noSchool, .pending, .none:
            return .none
        }
    }

    static func action(for date: Date, in settings: SchoolScheduleStore, calendar: Calendar) -> CalendarSchoolDayHoverAction {
        action(
            baseStatus: settings.baseSchoolCalendar.effectiveSchoolStatus(for: date, calendar: calendar),
            personalOverride: settings.personalOverride(for: SchoolDate(date, calendar: calendar))
        )
    }

    func headerEntered(_ date: Date, action: CalendarSchoolDayHoverAction) {
        guard action != .none else { dismiss(); return }
        cancelDismissal()
        activeDate = date
        hoveredHeaderDate = date
        if hoveredActionDate != date { hoveredActionDate = nil }
    }

    func headerExited(_ date: Date) {
        if hoveredHeaderDate == date { hoveredHeaderDate = nil }
        guard activeDate == date else { return }
        scheduleDismissal()
    }

    func actionEntered(_ date: Date) {
        guard activeDate == date else { return }
        hoveredActionDate = date
        cancelDismissal()
    }

    func actionExited(_ date: Date) {
        if hoveredActionDate == date { hoveredActionDate = nil }
        guard activeDate == date else { return }
        scheduleDismissal()
    }

    func performAction(in settings: SchoolScheduleStore, calendar: Calendar) {
        // Re-resolve the base and personal choice at activation, including any
        // pending/holiday update that arrived after entering the header.
        if let date = activeDate {
            let key = SchoolDate(date, calendar: calendar)
            switch Self.action(for: date, in: settings, calendar: calendar) {
            case .markNoSchool:
                settings.resolve(key, as: .noSchool)
            case .restoreSchoolCalendar:
                settings.removePersonalOverride(for: key)
            case .none:
                break
            }
        }
        dismiss()
    }

    func dismiss() {
        cancelDismissal()
        activeDate = nil
        hoveredHeaderDate = nil
        hoveredActionDate = nil
    }

    private func cancelDismissal() {
        dismissalTask?.cancel()
        dismissalTask = nil
    }

    private func scheduleDismissal() {
        cancelDismissal()
        guard let activeDate, hoveredHeaderDate != activeDate, hoveredActionDate != activeDate else { return }
        dismissalTask = Task { [weak self, dismissalDelay] in
            do { try await Task.sleep(for: dismissalDelay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
