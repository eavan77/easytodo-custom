import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        EasyTODOSettings.registerDefaults()
        AppLogo.applyApplicationIcon()
        MenuBarManager.shared.applicationDidFinishLaunching()
        GlobalShortcutManager.shared.registerQuickAddShortcut()
        WindowManager.shared.applyActivationPolicy()
        WindowManager.shared.prepareLauncherFirstStartup()
        WidgetWindowManager.shared.showWidget()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcutManager.shared.unregisterQuickAddShortcut()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
