import AppKit
import SwiftUI

@MainActor
final class AboutWindowManager: NSObject, NSWindowDelegate {
    static let shared = AboutWindowManager()
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 330),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "About EasyTODO"
        window.contentViewController = NSHostingController(rootView: AboutEasyTODOView())
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}

private struct AboutEasyTODOView: View {
    private let info = Bundle.main.infoDictionary ?? [:]
    private var version: String { info["CFBundleShortVersionString"] as? String ?? "Development" }
    private var build: String { info["CFBundleVersion"] as? String ?? "Local" }
    private var gitHash: String { info["EasyTODOGitHash"] as? String ?? "Unavailable" }
    private var buildDate: String { info["EasyTODOBuildDate"] as? String ?? "Unavailable" }
    private var executablePath: String { Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? "Unknown" }
    private var appPath: String {
        let marker = ".app/Contents/MacOS/"
        guard let range = executablePath.range(of: marker) else { return executablePath }
        return String(executablePath[..<range.lowerBound]) + ".app"
    }
    private var isCanonical: Bool { appPath == "/Applications/EasyTODO.app" }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("EasyTODO").font(.title2.weight(.semibold))
            if !isCanonical {
                Text("Development Build").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                row("Version", version)
                row("Build", build)
                row("Git", gitHash)
                row("Built", buildDate)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Running from").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(appPath).font(.caption.monospaced()).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24).frame(width: 430, height: 330)
    }

    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }
    }
}
