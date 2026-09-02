import SwiftUI

struct SettingsView: View {
    @AppStorage(EasyTODOSettings.launchAtLogin) private var launchAtLogin = false
    @AppStorage(EasyTODOSettings.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(EasyTODOSettings.showMenuBar) private var showMenuBar = true
    @AppStorage(EasyTODOSettings.hiddenDockIcon) private var hiddenDockIcon = false
    @AppStorage(EasyTODOSettings.transparency) private var transparency = 0.80
    @AppStorage(EasyTODOSettings.theme) private var theme = ThemeOption.light.rawValue
    @AppStorage(EasyTODOSettings.widgetActiveOpacity) private var widgetActiveOpacity = 1.0
    @AppStorage(EasyTODOSettings.widgetInactiveOpacity) private var widgetInactiveOpacity = 0.45

    @State private var loginItemMessage: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Always on Top", isOn: $alwaysOnTop)
                Toggle("Show in Menu Bar", isOn: $showMenuBar)
                Toggle("Hide Dock Icon", isOn: $hiddenDockIcon)
                    .disabled(!showMenuBar)

                Text("Quick Add: \(GlobalShortcutManager.quickAddShortcutDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let loginItemMessage {
                    Text(loginItemMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Transparency") {
                Picker("Window", selection: $transparency) {
                    Text("100%").tag(1.0)
                    Text("80%").tag(0.80)
                    Text("50%").tag(0.50)
                }
                .pickerStyle(.segmented)

                LabeledContent("Active widget") {
                    Slider(value: $widgetActiveOpacity, in: 0.65...1.0, step: 0.05)
                    Text(widgetActiveOpacity, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
                LabeledContent("Inactive widget") {
                    Slider(value: $widgetInactiveOpacity, in: 0.25...0.70, step: 0.05)
                    Text(widgetInactiveOpacity, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                }
            }

            Section("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onChange(of: launchAtLogin) { _, newValue in
            loginItemMessage = LoginItemManager.setEnabled(newValue)
        }
        .onChange(of: alwaysOnTop) { _, _ in
            WindowManager.shared.applyWindowSettings()
        }
        .onChange(of: transparency) { _, _ in
            WindowManager.shared.applyWindowSettings()
        }
        .onChange(of: widgetActiveOpacity) { _, _ in WidgetWindowManager.shared.applyWidgetTransparency() }
        .onChange(of: widgetInactiveOpacity) { _, _ in WidgetWindowManager.shared.applyWidgetTransparency() }
        .onChange(of: showMenuBar) { _, newValue in
            if !newValue {
                hiddenDockIcon = false
            }

            WindowManager.shared.applyActivationPolicy()
        }
        .onChange(of: hiddenDockIcon) { _, _ in
            WindowManager.shared.applyActivationPolicy()
        }
    }
}
