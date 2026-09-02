import Foundation
import SwiftData
import SwiftUI

@Model
final class TaskCategory {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorIdentifier: String
    var sortOrder: Int
    @Relationship(deleteRule: .nullify, inverse: \TodoTask.category) var tasks: [TodoTask] = []

    init(id: UUID = UUID(), name: String, colorIdentifier: String = CategoryColor.blue.rawValue, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorIdentifier = colorIdentifier
        self.sortOrder = sortOrder
    }

    var color: CategoryColor {
        get { CategoryColor(rawValue: colorIdentifier) ?? .blue }
        set { colorIdentifier = newValue.rawValue }
    }
}

enum CategoryColor: String, CaseIterable, Identifiable {
    case blue, green, orange, purple, pink, teal, yellow, gray
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .purple: .purple
        case .pink: .pink
        case .teal: .teal
        case .yellow: .yellow
        case .gray: .gray
        }
    }
}
