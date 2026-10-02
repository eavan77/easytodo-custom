import Foundation

struct CalendarWeek: Equatable, Sendable {
    let days: [Date]
    let interval: DateInterval

    init(containing date: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: date)
        let offset = calendar.component(.weekday, from: day) - 1
        let start = calendar.date(byAdding: .day, value: -offset, to: day)!
        days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        interval = DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }
}

struct WeeklySchoolSchedule {
    struct Day: Identifiable {
        let date: Date
        let school: SchoolDay?
        let events: [CalendarGlanceEvent]
        var id: Date { date }
    }

    let days: [Day]
    let calendar: Calendar
    let lunchWindow: SchoolLunchWindow?
    let placements: [String: SpecialEventBand]

    init(week: CalendarWeek, school: SchoolCalendar, timetable: SchoolTimetable,
         events: [CalendarGlanceEvent], calendar: Calendar,
         lunchWindow: SchoolLunchWindow?, placements: [String: SpecialEventBand]) {
        self.calendar = calendar
        self.lunchWindow = lunchWindow
        self.placements = placements
        let snapshot = CalendarEventSnapshot(range: week.interval, events: events)
        days = week.days.map { date in
            let end = calendar.date(byAdding: .day, value: 1, to: date)!
            return Day(date: date, school: school.day(on: date, timetable: timetable, calendar: calendar),
                       events: snapshot.events(in: DateInterval(start: date, end: end)))
        }
    }

    var pendingDates: [SchoolDate] {
        days.filter { $0.school?.status == .pending }.map { SchoolDate($0.date, calendar: calendar) }
    }

    var expandsLunch: Bool {
        days.contains { !events(on: $0, in: .lunch).isEmpty }
    }

    func events(on day: Day, in band: SpecialEventBand) -> [CalendarGlanceEvent] {
        day.events.filter { self.band(for: $0, on: day.date) == band }
    }

    func band(for event: CalendarGlanceEvent, on day: Date) -> SpecialEventBand {
        // All-day overlays never expand lunch. Placement is per occurrence.
        if event.isAllDay { return .unplaced }
        if let key = event.mappingKey, let placement = placements[key] { return placement }
        guard let lunchWindow else { return .unplaced }
        let lunch = lunchWindow.interval(on: day, calendar: calendar)
        if event.start < lunch.end && (event.end > lunch.start || event.start >= lunch.start) {
            return .lunch
        }
        return event.end <= lunch.start ? .beforeLunch : .afterLunch
    }
}
