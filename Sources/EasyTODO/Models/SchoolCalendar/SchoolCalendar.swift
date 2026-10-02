import Foundation

// Civil dates deliberately contain no time zone or clock time. Convert using
// the Calendar supplied by the caller (UI now; planner bridge in a later phase).
struct SchoolDate: Hashable, Codable, Comparable, Identifiable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }

    var id: String { String(format: "%04d-%02d-%02d", year, month, day) }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

enum SchoolDayStatus: Equatable, Codable, Sendable {
    case regularSchoolDay
    case replacementSchoolDay(SchoolWeekday)
    case noSchool
    case pending
}

enum SchoolDayResolution: Sendable {
    case normalSchool
    case noSchool
    case useTimetable(SchoolWeekday)

    var status: SchoolDayStatus {
        switch self {
        case .normalSchool: .regularSchoolDay
        case .noSchool: .noSchool
        case .useTimetable(let weekday): .replacementSchoolDay(weekday)
        }
    }
}

struct SchoolDay: Sendable {
    let status: SchoolDayStatus
    // nil explicitly means unresolved; [] means confirmed with no classes.
    let lessons: [SchoolLesson]?
}

struct SchoolCalendar: Codable, Sendable {
    var overrides: [SchoolDate: SchoolDayStatus]
    var holidayStart: SchoolDate?
    // This calendar belongs to S1 only. No S2 dates/boundaries were supplied.
    // When set, dates outside the semester return nil, not fabricated pending.
    var semesterEnd: SchoolDate?
    var personalOverrides: [SchoolDate: SchoolDayStatus]? = nil

    func effectiveSchoolStatus(for date: Date, calendar: Calendar = .current) -> SchoolDayStatus? {
        let key = SchoolDate(date, calendar: calendar)
        if let personal = personalOverrides?[key] { return personal }
        if let semesterEnd, key > semesterEnd { return nil }
        let weekday = SchoolWeekday(rawValue: calendar.component(.weekday, from: date))!
        if let override = overrides[key] {
            return override
        } else if let holidayStart, key >= holidayStart {
            return .noSchool
        } else {
            return weekday == .saturday || weekday == .sunday ? .noSchool : .regularSchoolDay
        }
    }

    func day(on date: Date, timetable: SchoolTimetable, calendar: Calendar) -> SchoolDay? {
        guard let status = effectiveSchoolStatus(for: date, calendar: calendar) else { return nil }
        let weekday = SchoolWeekday(rawValue: calendar.component(.weekday, from: date))!
        switch status {
        case .regularSchoolDay:
            return SchoolDay(status: status, lessons: timetable.lessons(on: weekday))
        case .replacementSchoolDay(let replacement):
            return SchoolDay(status: status, lessons: timetable.lessons(on: replacement))
        case .noSchool:
            return SchoolDay(status: status, lessons: [])
        case .pending:
            return SchoolDay(status: status, lessons: nil)
        }
    }

    mutating func resolve(_ date: SchoolDate, as resolution: SchoolDayResolution) {
        overrides[date] = resolution.status
    }

    func pendingDates(from first: SchoolDate, through last: SchoolDate) -> [SchoolDate] {
        overrides.compactMap { date, status in
            guard status == .pending, personalOverrides?[date] == nil, date >= first, date <= last,
                  semesterEnd.map({ date <= $0 }) ?? true else { return nil }
            return date
        }.sorted()
    }

    static var semester1: SchoolCalendar {
        var overrides: [SchoolDate: SchoolDayStatus] = [
            SchoolDate(2026, 9, 28): .regularSchoolDay,
            SchoolDate(2026, 9, 29): .noSchool,
            SchoolDate(2026, 9, 30): .noSchool,
            SchoolDate(2026, 10, 10): .replacementSchoolDay(.wednesday),
            SchoolDate(2026, 10, 30): .noSchool,
            SchoolDate(2026, 11, 11): .noSchool
        ]
        for day in 1...6 { overrides[SchoolDate(2026, 10, day)] = .noSchool }
        for day in 14...18 { overrides[SchoolDate(2026, 12, day)] = .noSchool }
        for day in 21...25 { overrides[SchoolDate(2026, 12, day)] = .noSchool }
        return SchoolCalendar(overrides: overrides, holidayStart: SchoolDate(2027, 1, 25), semesterEnd: nil)
    }
}
