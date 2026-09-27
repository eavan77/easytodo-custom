import Foundation
import SwiftData

@Model
final class DayCapacityTemplate {
    var weekday: Int
    var kindRawValue: String
    var deepCapacity: Int
    var mediumCapacity: Int
    var fragmentCapacity: Int
    var preferredDeepPeriodsRawValue: String
    var deepPeriodMinutesRawValue: String?
    var mediumPeriodMinutesRawValue: String?
    var fragmentPeriodMinutesRawValue: String?
    var fixedCommitmentsRawValue: String
    var cognitiveLoadFromCommitments: Int

    init(
        weekday: Int,
        kind: DayTemplateKind,
        deepCapacity: Int,
        mediumCapacity: Int,
        fragmentCapacity: Int,
        preferredDeepPeriods: [WorkBlockPeriod],
        deepPeriodMinutes: [Int]? = nil,
        mediumPeriodMinutes: [Int]? = nil,
        fragmentPeriodMinutes: [Int]? = nil,
        fixedCommitments: [String] = [],
        cognitiveLoadFromCommitments: Int
    ) {
        self.weekday = weekday
        self.kindRawValue = kind.rawValue
        self.deepCapacity = deepCapacity
        self.mediumCapacity = mediumCapacity
        self.fragmentCapacity = fragmentCapacity
        self.preferredDeepPeriodsRawValue = preferredDeepPeriods.map(\.rawValue).joined(separator: ",")
        self.deepPeriodMinutesRawValue = deepPeriodMinutes.map(Self.encodeMinutes)
        self.mediumPeriodMinutesRawValue = mediumPeriodMinutes.map(Self.encodeMinutes)
        self.fragmentPeriodMinutesRawValue = fragmentPeriodMinutes.map(Self.encodeMinutes)
        self.fixedCommitmentsRawValue = fixedCommitments.joined(separator: "\n")
        self.cognitiveLoadFromCommitments = cognitiveLoadFromCommitments
    }

    var kind: DayTemplateKind {
        get { DayTemplateKind(rawValue: kindRawValue) ?? .custom }
        set { kindRawValue = newValue.rawValue }
    }

    var preferredDeepPeriods: [WorkBlockPeriod] {
        get { preferredDeepPeriodsRawValue.split(separator: ",").compactMap { WorkBlockPeriod(rawValue: String($0)) } }
        set { preferredDeepPeriodsRawValue = newValue.map(\.rawValue).joined(separator: ",") }
    }

    var fixedCommitments: [String] {
        get { fixedCommitmentsRawValue.split(separator: "\n").map(String.init) }
        set { fixedCommitmentsRawValue = newValue.joined(separator: "\n") }
    }

    var deepPeriodMinutes: [Int] {
        resolvedMinutes(deepPeriodMinutesRawValue, count: deepCapacity, defaultMinutes: 120)
    }

    var mediumPeriodMinutes: [Int] {
        resolvedMinutes(mediumPeriodMinutesRawValue, count: mediumCapacity, defaultMinutes: 90)
    }

    var fragmentPeriodMinutes: [Int] {
        resolvedMinutes(fragmentPeriodMinutesRawValue, count: fragmentCapacity, defaultMinutes: 30)
    }

    private func resolvedMinutes(_ rawValue: String?, count: Int, defaultMinutes: Int) -> [Int] {
        let stored = (rawValue ?? "").split(separator: ",").compactMap { Int($0) }.filter { $0 > 0 }
        if stored.count >= count { return Array(stored.prefix(max(0, count))) }
        return stored + Array(repeating: defaultMinutes, count: max(0, count - stored.count))
    }

    private static func encodeMinutes(_ values: [Int]) -> String {
        values.filter { $0 > 0 }.map(String.init).joined(separator: ",")
    }
}

enum DefaultCapacityProfile {
    static func templates() -> [DayCapacityTemplate] {
        (1...7).map { weekday in
            switch weekday {
            case 2, 3, 4:
                DayCapacityTemplate(weekday: weekday, kind: .school, deepCapacity: 1, mediumCapacity: 1,
                                    fragmentCapacity: 2, preferredDeepPeriods: [.evening],
                                    fixedCommitments: ["School", "Protected rest 21:00–22:00"], cognitiveLoadFromCommitments: 3)
            case 5:
                DayCapacityTemplate(weekday: weekday, kind: .school, deepCapacity: 1, mediumCapacity: 2,
                                    fragmentCapacity: 2, preferredDeepPeriods: [.evening],
                                    fixedCommitments: ["School", "Protected rest 21:00–22:00"], cognitiveLoadFromCommitments: 2)
            default:
                DayCapacityTemplate(weekday: weekday, kind: .free, deepCapacity: 2, mediumCapacity: 2,
                                    fragmentCapacity: 3, preferredDeepPeriods: [.deep1, .deep2],
                                    fixedCommitments: ["Protected rest 21:00–22:00"], cognitiveLoadFromCommitments: 0)
            }
        }
    }
}
