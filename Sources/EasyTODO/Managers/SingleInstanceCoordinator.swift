import AppKit

@MainActor
final class SingleInstanceCoordinator {
    static let shared = SingleInstanceCoordinator()
    static let bundleIdentifier = "com.easytodo.EasyTODO"

    private var pendingPIDs = Set<pid_t>()
    private var terminationObserver: NSObjectProtocol?
    private var readyAction: (() -> Void)?

    private init() {}

    /// The newest matching application wins. Its UI is installed only after
    /// older processes with the exact bundle identifier have terminated.
    func prepareCurrentInstance(whenReady: @escaping () -> Void) {
        guard Bundle.main.bundleIdentifier == Self.bundleIdentifier else {
            whenReady()
            return
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
        guard Self.winningPID(in: matches) == currentPID else {
            matches.first { $0.processIdentifier == Self.winningPID(in: matches) }?
                .activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        let older = matches.filter { $0.processIdentifier != currentPID && !$0.isTerminated }
        guard !older.isEmpty else {
            whenReady()
            return
        }

        readyAction = whenReady
        pendingPIDs = Set(older.map(\.processIdentifier))
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in SingleInstanceCoordinator.shared.applicationTerminated(pid: app.processIdentifier) }
        }

        for app in older where !app.forceTerminate() {
            pendingPIDs.remove(app.processIdentifier)
        }
        finishIfReady()
    }

    static func winningPID(in applications: [NSRunningApplication]) -> pid_t? {
        applications.max {
            let lhsDate = $0.launchDate ?? .distantPast
            let rhsDate = $1.launchDate ?? .distantPast
            return lhsDate == rhsDate ? $0.processIdentifier < $1.processIdentifier : lhsDate < rhsDate
        }?.processIdentifier
    }

    private func applicationTerminated(pid: pid_t) {
        pendingPIDs.remove(pid)
        finishIfReady()
    }

    private func finishIfReady() {
        guard pendingPIDs.isEmpty, let action = readyAction else { return }
        readyAction = nil
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        action()
    }
}
