import Foundation

struct CalendarWeekNavigation {
    private(set) var selectedDate: Date
    private(set) var followsToday = true

    init(now: Date = .now) { selectedDate = now }

    func week(calendar: Calendar) -> CalendarWeek {
        CalendarWeek(containing: selectedDate, calendar: calendar)
    }

    mutating func move(by weeks: Int, calendar: Calendar) {
        selectedDate = calendar.date(byAdding: .day, value: weeks * 7, to: selectedDate)!
        followsToday = false
    }

    mutating func showToday(now: Date = .now) {
        selectedDate = now
        followsToday = true
    }

    mutating func show(_ date: Date, now: Date = .now, calendar: Calendar) {
        selectedDate = date
        followsToday = CalendarWeek(containing: date, calendar: calendar) == CalendarWeek(containing: now, calendar: calendar)
    }

    mutating func refresh(now: Date = .now) {
        if followsToday { selectedDate = now }
    }
}
