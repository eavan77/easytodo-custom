import AppKit
import QuartzCore
import SwiftData

@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private var panel: NSPanel?
    private var contentView: NotchTrackingView?
    private var modelContainer: ModelContainer?

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    private let pointerMonitor = NotchPointerMonitor()

    private var isExpanded = false
    private var pendingExpansion: DispatchWorkItem?
    private var pendingCollapse: DispatchWorkItem?

    private let expansionDelay: TimeInterval = 0.06
    private let collapseDelay: TimeInterval = 0.30
    private let expansionAnimationDuration: TimeInterval = 0.13
    private let collapseAnimationDuration: TimeInterval = 0.11

    private init() {}

    func show() {
        guard let geometry = NotchGeometry.builtIn else {
            NSLog("[Notch] No supported notched display found.")
            return
        }

        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: geometry.collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.identifier = NSUserInterfaceItemIdentifier("easy-todo-notch-window")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false

        let contentView = NotchTrackingView(
            frame: NSRect(
                origin: .zero,
                size: geometry.collapsedFrame.size
            )
        )

        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        contentView.layer?.cornerRadius = 10
        contentView.layer?.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner
        ]
        contentView.layer?.masksToBounds = true

        guard let modelContainer else {
            NSLog("[Notch] ModelContainer was not configured.")
            return
        }

        contentView.installHub(modelContainer: modelContainer)
        contentView.setHubVisible(false)

        // NSTrackingArea no longer controls presentation.
        contentView.onMouseEntered = nil
        contentView.onMouseExited = nil

        panel.contentView = contentView

        self.panel = panel
        self.contentView = contentView

        pointerMonitor.onPointerMoved = { [weak self] location in
            self?.handlePointer(
                location,
                geometry: geometry
            )
        }

        pointerMonitor.start()
        panel.orderFrontRegardless()
    }

    private func handlePointer(
        _ location: NSPoint,
        geometry: NotchGeometry
    ) {
        guard let panel, let contentView else { return }

        if isExpanded {
            if panel.frame.contains(location) {
                cancelCollapse()
            } else {
                scheduleCollapse(
                    panel: panel,
                    contentView: contentView,
                    geometry: geometry
                )
            }
        } else {
            if geometry.hoverTriggerFrame.contains(location) {
                scheduleExpansion(
                    panel: panel,
                    contentView: contentView,
                    geometry: geometry
                )
            } else {
                cancelExpansion()
            }
        }
    }

    private func scheduleExpansion(
        panel: NSPanel,
        contentView: NotchTrackingView,
        geometry: NotchGeometry
    ) {
        guard pendingExpansion == nil else { return }

        cancelCollapse()

        let work = DispatchWorkItem { [weak self, weak panel, weak contentView] in
            guard let self, let panel, let contentView else { return }

            self.pendingExpansion = nil

            let pointer = NSEvent.mouseLocation
            guard geometry.hoverTriggerFrame.contains(pointer) else { return }

            self.isExpanded = true

            self.animateExpansion(
                panel: panel,
                contentView: contentView,
                to: geometry.expandedFrame
            )

            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.expansionAnimationDuration
            ) { [weak self, weak contentView] in
                guard let self, let contentView, self.isExpanded else { return }
                contentView.setHubVisible(true)
            }
        }

        pendingExpansion = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + expansionDelay,
            execute: work
        )
    }

    private func scheduleCollapse(
        panel: NSPanel,
        contentView: NotchTrackingView,
        geometry: NotchGeometry
    ) {
        guard pendingCollapse == nil else { return }

        cancelExpansion()

        let work = DispatchWorkItem { [weak self, weak panel, weak contentView] in
            guard let self, let panel, let contentView else { return }

            self.pendingCollapse = nil

            let pointer = NSEvent.mouseLocation
            guard !panel.frame.contains(pointer) else { return }

            self.isExpanded = false
            contentView.setHubVisible(false)

            self.animateCollapse(
                panel: panel,
                contentView: contentView,
                to: geometry.collapsedFrame
            )
        }

        pendingCollapse = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + collapseDelay,
            execute: work
        )
    }

    private func cancelExpansion() {
        pendingExpansion?.cancel()
        pendingExpansion = nil
    }

    private func cancelCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }

    private func animateExpansion(
        panel: NSPanel,
        contentView: NotchTrackingView,
        to targetFrame: NSRect
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            panel.animator().setFrame(targetFrame, display: true)
            contentView.layer?.cornerRadius = 18
        }
    }

    private func animateCollapse(
        panel: NSPanel,
        contentView: NotchTrackingView,
        to targetFrame: NSRect
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = collapseAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)

            panel.animator().setFrame(targetFrame, display: true)
            contentView.layer?.cornerRadius = 10
        }
    }
}
