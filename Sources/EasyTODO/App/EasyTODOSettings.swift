import Foundation

enum EasyTODOSettings {
    static let launchAtLogin = "launchAtLogin"
    static let alwaysOnTop = "alwaysOnTop"
    static let showMenuBar = "showMenuBar"
    static let hiddenDockIcon = "hiddenDockIcon"
    static let transparency = "transparency"
    static let widgetTransparency = "widgetTransparency"
    static let widgetActiveOpacity = "widgetActiveOpacity"
    static let widgetInactiveOpacity = "widgetInactiveOpacity"
    static let widgetCategoryFilter = "widgetCategoryFilter"
    private static let widgetOpacityDefaultsVersion = "widgetOpacityDefaultsVersion"
    static let theme = "theme"

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            launchAtLogin: false,
            alwaysOnTop: true,
            showMenuBar: true,
            hiddenDockIcon: false,
            transparency: 0.80,
            widgetTransparency: 0.80,
            widgetActiveOpacity: 1.0,
            widgetInactiveOpacity: WidgetOpacityPolicy.defaultInactive,
            widgetCategoryFilter: "all",
            theme: ThemeOption.light.rawValue
        ])

        if defaults.integer(forKey: widgetOpacityDefaultsVersion) < 2 {
            defaults.set(WidgetOpacityPolicy.defaultInactive, forKey: widgetInactiveOpacity)
            defaults.set(2, forKey: widgetOpacityDefaultsVersion)
        }

        if abs(defaults.double(forKey: transparency) - 0.90) < 0.001 {
            defaults.set(0.80, forKey: transparency)
        }

        if ThemeOption(rawValue: defaults.string(forKey: theme) ?? "") == nil {
            defaults.set(ThemeOption.light.rawValue, forKey: theme)
        }
    }
}

enum WidgetOpacityPolicy {
    static let defaultActive = 1.0
    static let defaultInactive = 0.08
    static let activeRange = 0.60...1.00
    static let inactiveRange = 0.05...0.50

    static func clampedActive(_ value: Double) -> Double { min(max(value, activeRange.lowerBound), activeRange.upperBound) }
    static func clampedInactive(_ value: Double) -> Double { min(max(value, inactiveRange.lowerBound), inactiveRange.upperBound) }
}

enum ThemeOption: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }
}
