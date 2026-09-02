import CoreGraphics
import Foundation

enum WidgetCorner: String, CaseIterable, Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static func quadrant(containing point: CGPoint, in visibleFrame: CGRect) -> WidgetCorner {
        let isLeft = point.x < visibleFrame.midX
        let isTop = point.y >= visibleFrame.midY

        return switch (isLeft, isTop) {
        case (true, true): .topLeft
        case (false, true): .topRight
        case (true, false): .bottomLeft
        case (false, false): .bottomRight
        }
    }
}

struct WidgetCornerStore {
    private let defaults: UserDefaults
    private let key = "widgetCorner"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WidgetCorner? {
        defaults.string(forKey: key).flatMap(WidgetCorner.init(rawValue:))
    }

    func save(_ corner: WidgetCorner) {
        defaults.set(corner.rawValue, forKey: key)
    }
}
