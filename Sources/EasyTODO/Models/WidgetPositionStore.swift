import CoreGraphics
import Foundation

struct WidgetPositionStore {
    private let defaults: UserDefaults
    private let xKey = "widgetTopRightAnchorX"
    private let yKey = "widgetTopRightAnchorY"
    private let savedKey = "widgetHasSavedAnchor"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CGPoint? {
        guard defaults.bool(forKey: savedKey) else { return nil }
        return CGPoint(x: defaults.double(forKey: xKey), y: defaults.double(forKey: yKey))
    }

    func save(_ anchor: CGPoint) {
        defaults.set(Double(anchor.x), forKey: xKey)
        defaults.set(Double(anchor.y), forKey: yKey)
        defaults.set(true, forKey: savedKey)
    }
}
