import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didInstallApplicationUI = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleInstanceCoordinator.shared.prepareCurrentInstance { [weak self] in
            self?.installApplicationUI()
        }
    }

    private func installApplicationUI() {
        guard !didInstallApplicationUI else { return }
        didInstallApplicationUI = true
        EasyTODOSettings.registerDefaults()
        AppLogo.applyApplicationIcon()
        MenuBarManager.shared.applicationDidFinishLaunching()
        GlobalShortcutManager.shared.registerQuickAddShortcut()
        WindowManager.shared.applyActivationPolicy()
        WindowManager.shared.prepareLauncherFirstStartup()
        WidgetWindowManager.shared.showWidget()
        if ProcessInfo.processInfo.arguments.contains("--widget-corner-diagnostics") {
            WidgetWindowManager.shared.runCornerDiagnostics()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcutManager.shared.unregisterQuickAddShortcut()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
