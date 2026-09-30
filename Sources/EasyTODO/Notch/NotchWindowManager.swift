import AppKit
import QuartzCore

@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private var panel: NSPanel?
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
            panel.setFrame(geometry.collapsedFrame, display: true)
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

        contentView.onMouseEntered = { [weak self, weak panel, weak contentView] in
            guard let self, let panel, let contentView else { return }

            self.pendingCollapse?.cancel()
            self.pendingCollapse = nil
            self.pendingExpansion?.cancel()

            let work = DispatchWorkItem { [weak self, weak panel, weak contentView] in
                guard let self, let panel, let contentView else { return }

                self.animateExpansion(
                    panel: panel,
                    contentView: contentView,
                    to: geometry.expandedFrame,
                    cornerRadius: 18
                )

                self.pendingExpansion = nil
            }

            self.pendingExpansion = work

            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.expansionDelay,
                execute: work
            )
        }

        contentView.onMouseExited = { [weak self, weak panel, weak contentView] in
            guard let self, let panel, let contentView else { return }

            self.pendingExpansion?.cancel()
            self.pendingExpansion = nil
            self.pendingCollapse?.cancel()

            let work = DispatchWorkItem { [weak self, weak panel, weak contentView] in
                guard let self, let panel, let contentView else { return }

                self.animateCollapse(
                    panel: panel,
                    contentView: contentView,
                    to: geometry.collapsedFrame,
                    cornerRadius: 10
                )

                self.pendingCollapse = nil
            }

            self.pendingCollapse = work

            DispatchQueue.main.asyncAfter(
                deadline: .now() + self.collapseDelay,
                execute: work
            )
        }

        panel.contentView = contentView
        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func animateExpansion(
        panel: NSPanel,
        contentView: NotchTrackingView,
        to targetFrame: NSRect,
        cornerRadius: CGFloat
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expansionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)

            panel.animator().setFrame(targetFrame, display: true)
            contentView.layer?.cornerRadius = cornerRadius
        }
    }

    private func animateCollapse(
        panel: NSPanel,
        contentView: NotchTrackingView,
        to targetFrame: NSRect,
        cornerRadius: CGFloat
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = collapseAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)

            panel.animator().setFrame(targetFrame, display: true)
            contentView.layer?.cornerRadius = cornerRadius
        }
    }
}
