import Foundation
import SwiftData

// One personal choice per civil date. The base calendar is never stored here.
@Model
final class SchoolStatusOverride {
    @Attribute(.unique) var dateKey: String
    var year: Int
    var month: Int
    var day: Int
    var statusRawValue: String
    var replacementWeekday: Int?

    init(date: SchoolDate, resolution: SchoolDayResolution) {
        dateKey = date.id
        year = date.year
        month = date.month
        day = date.day
        statusRawValue = "regularSchoolDay"
        setResolution(resolution)
    }

    var schoolDate: SchoolDate { SchoolDate(year, month, day) }

    var status: SchoolDayStatus? {
        switch statusRawValue {
        case "regularSchoolDay": .regularSchoolDay
        case "noSchool": .noSchool
        case "replacementSchoolDay": replacementWeekday.flatMap(SchoolWeekday.init(rawValue:)).map(SchoolDayStatus.replacementSchoolDay)
        default: nil
        }
    }

    func setResolution(_ resolution: SchoolDayResolution) {
        replacementWeekday = nil
        switch resolution {
        case .normalSchool: statusRawValue = "regularSchoolDay"
        case .noSchool: statusRawValue = "noSchool"
        case .useTimetable(let weekday):
            statusRawValue = "replacementSchoolDay"
            replacementWeekday = weekday.rawValue
        }
    }
}
