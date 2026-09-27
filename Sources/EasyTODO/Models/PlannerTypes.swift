import Foundation

enum DeadlineType: String, CaseIterable, Codable, Identifiable {
    case hard, soft, internalDeadline = "internal", none
    var id: String { rawValue }
    var title: String { rawValue == "internal" ? "Internal" : rawValue.capitalized }
}

enum DeadlineTypeSource: String, Codable, Identifiable {
    case userSelected, autoDetected, legacyFallback, unknown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .userSelected: "User selected"
        case .autoDetected: "Auto-detected"
        case .legacyFallback: "Needs confirmation"
        case .unknown: "Unknown"
        }
    }
}

enum WorkMode: String, CaseIterable, Codable, Identifiable {
    case deep, medium, fragmentable
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TaskSize: String, CaseIterable, Codable, Identifiable {
    case small = "S", medium = "M", large = "L", extraLarge = "XL"
    var id: String { rawValue }
}

enum EnergyDemand: String, CaseIterable, Codable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PlanningUncertainty: String, CaseIterable, Codable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WorkBlockPeriod: String, CaseIterable, Codable, Identifiable {
    case morning, afternoon, evening, schoolFragment = "school_fragment"
    case deep1 = "deep_1", deep2 = "deep_2", flexible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .schoolFragment: "School fragment"
        case .deep1: "Deep 1"
        case .deep2: "Deep 2"
        default: rawValue.capitalized
        }
    }

    var planningOrder: Int {
        switch self {
        case .morning: 0
        case .deep1: 1
        case .schoolFragment: 2
        case .afternoon: 3
        case .deep2: 4
        case .evening: 5
        case .flexible: 6
        }
    }
}

enum WorkBlockStatus: String, CaseIterable, Codable, Identifiable {
    case planned, active, done, skipped, moved
    var id: String { rawValue }
}

enum DayTemplateKind: String, CaseIterable, Codable, Identifiable {
    case school, free, custom
    var id: String { rawValue }
    var title: String { "\(rawValue.capitalized) day" }
}

enum TaskPlanSort: String, CaseIterable, Identifiable {
    case plan = "Plan", due = "Due", project = "Project"
    var id: String { rawValue }
}

enum PlannerMainView: String, CaseIterable, Identifiable {
    case focus, tasks, week
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
