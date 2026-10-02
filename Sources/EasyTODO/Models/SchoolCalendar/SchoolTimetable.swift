import Foundation

enum SchoolWeekday: Int, CaseIterable, Codable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var title: String {
        ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][rawValue - 1]
    }
}

enum SchoolSession: String, Codable, Sendable {
    case beforeLunch, afterLunch
}

struct SchoolLesson: Codable, Equatable, Identifiable, Sendable {
    // School periods determine order and lunch placement, never UI clock times.
    var period: Int
    var course: String
    var id: Int { period }
    var session: SchoolSession { period <= 5 ? .beforeLunch : .afterLunch }
}

struct SchoolTimetable: Codable, Sendable {
    var days: [SchoolWeekday: [SchoolLesson]]

    func lessons(on weekday: SchoolWeekday) -> [SchoolLesson] {
        (days[weekday] ?? []).sorted { $0.period < $1.period }
    }

    // Authoritative personal timetable, manually confirmed by the user.
    static let semester1 = SchoolTimetable(days: [
        .monday: [
            SchoolLesson(period: 1, course: "Lit"),
            SchoolLesson(period: 4, course: "Research"),
            SchoolLesson(period: 5, course: "CM")
        ],
        .tuesday: [
            SchoolLesson(period: 1, course: "Adv.Math"),
            SchoolLesson(period: 4, course: "Lit"),
            SchoolLesson(period: 5, course: "PE"),
            SchoolLesson(period: 6, course: "Man")
        ],
        .wednesday: [
            SchoolLesson(period: 1, course: "Adv.Math"),
            SchoolLesson(period: 4, course: "Psy"),
            SchoolLesson(period: 6, course: "Research")
        ],
        .thursday: [
            SchoolLesson(period: 1, course: "Psy"),
            SchoolLesson(period: 3, course: "PE")
        ],
        .friday: [], .saturday: [], .sunday: []
    ])
}
