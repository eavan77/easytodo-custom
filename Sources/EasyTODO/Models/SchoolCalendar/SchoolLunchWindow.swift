import Foundation

enum SpecialEventBand: String, Codable, CaseIterable, Sendable {
    case beforeLunch, lunch, afterLunch, unplaced

    var title: String {
        switch self {
        case .beforeLunch: "Before lunch"
        case .lunch: "Lunch"
        case .afterLunch: "After lunch"
        case .unplaced: "Separate from classes"
        }
    }
}

struct SchoolLunchWindow: Codable, Equatable, Sendable {
    let startMinute: Int
    let endMinute: Int

    init?(startMinute: Int, endMinute: Int) {
        guard (0..<1440).contains(startMinute), endMinute > startMinute, endMinute < 1440 else { return nil }
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    func interval(on day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day)!
        let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: day)!
        return DateInterval(start: start, end: end)
    }
}

