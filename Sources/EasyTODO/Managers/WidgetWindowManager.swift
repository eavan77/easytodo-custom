import AppKit
import SwiftData
import SwiftUI

@MainActor
final class WidgetWindowManager {
    static let shared = WidgetWindowManager()

    private var modelContainer: ModelContainer?
    private var widgetWindow: NSPanel?
    private var contextMenuController: WidgetContextMenuController?
    private var pendingCollapse: DispatchWorkItem?
    private var pendingVisualCollapse: DispatchWorkItem?
    private var menuObservers: [NSObjectProtocol] = []
    private(set) var hoverState = WidgetHoverState()
    private var topRightAnchor: CGPoint?
    private let positionStore = WidgetPositionStore()

    private let expandedSize = NSSize(width: 276, height: 350)
    private let launcherSize = NSSize(width: 40, height: 40)
    private let edgeInset: CGFloat = 16
    private let collapseDelay = 0.45
    private let presentationDuration = 0.28

    private init() {
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetWindowManager.shared.beginChildInteraction() }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetWindowManager.shared.endChildInteraction() }
            }
        ]
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Shows the stable top-right launcher. Hovering it expands the same panel.
    func showWidget() {
        guard let modelContainer else {
            NSLog("EasyTODO widget cannot open before SwiftData is configured.")
            return
        }

        if widgetWindow == nil {
            createPanel(modelContainer: modelContainer)
        }

        guard let panel = widgetWindow else { return }
        cancelPendingCollapse()
        cancelPendingVisualCollapse()
        hoverState.show()
        applyGeometry(panel, visibility: .launcher, notify: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func toggleWidget() {
        hoverState.visibility == .hidden ? showWidget() : hideWidget()
    }

    func hideWidget() {
        cancelPendingCollapse()
        cancelPendingVisualCollapse()
        hoverState.hide()
        notifyPresentationChanged()
        widgetWindow?.orderOut(nil)
    }

    func pointerEntered() {
        guard hoverState.visibility != .hidden else { return }
        cancelPendingCollapse()
        let wasLauncher = hoverState.visibility == .launcher
        hoverState.pointerEntered()
        if wasLauncher, let panel = widgetWindow {
            expand(panel)
        }
    }

    func pointerExited() {
        hoverState.pointerExited()
        scheduleCollapseIfNeeded()
    }

    func beginChildInteraction() {
        cancelPendingCollapse()
        hoverState.beginInteraction()
    }

    func endChildInteraction() {
        hoverState.endInteraction()
        scheduleCollapseIfNeeded()
    }

    func beginWidgetDrag() {
        beginChildInteraction()
    }

    func finishWidgetDrag() {
        guard let panel = widgetWindow else {
            endChildInteraction()
            return
        }
        let screen = bestScreen(for: panel.frame)
        let clampedFrame = WidgetPanelGeometry.clampedFrame(panel.frame, to: screen.visibleFrame)
        panel.setFrame(clampedFrame, display: true, animate: false)
        let anchor = WidgetPanelGeometry.topRightAnchor(for: clampedFrame)
        topRightAnchor = anchor
        positionStore.save(anchor)
        endChildInteraction()
    }

    fileprivate func activateForInteraction() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func showContextMenu(for event: NSEvent, in panel: NSPanel) {
        beginChildInteraction()
        defer { endChildInteraction() }

        let controller = WidgetContextMenuController()
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Full App", action: #selector(WidgetContextMenuController.openMainApp), keyEquivalent: "")
        openItem.target = controller
        menu.addItem(openItem)
        menu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Hide Widget", action: #selector(WidgetContextMenuController.hideWidget), keyEquivalent: "")
        hideItem.target = controller
        menu.addItem(hideItem)
        contextMenuController = controller
        menu.popUp(positioning: nil, at: event.locationInWindow, in: panel.contentView)
    }

    private func createPanel(modelContainer: ModelContainer) {
        let panel = WidgetPanel(
            contentRect: launcherFrame(on: preferredScreen()),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("easy-todo-widget-window")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.alphaValue = 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        let hostingView = WidgetTrackingHostingView(
            rootView: WidgetRootView().modelContainer(modelContainer)
        )
        hostingView.frame = NSRect(origin: .zero, size: launcherSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        widgetWindow = panel
    }

    private func scheduleCollapseIfNeeded() {
        cancelPendingCollapse()
        guard hoverState.isCollapsePending else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.completeCollapseGracePeriod() }
        }
        pendingCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
    }

    private func completeCollapseGracePeriod() {
        hoverState.collapseGracePeriodCompleted()
        guard hoverState.visibility == .launcher, let panel = widgetWindow else { return }
        pendingCollapse = nil
        beginAnimatedCollapse(panel)
    }

    private func cancelPendingCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }
    private func cancelPendingVisualCollapse() {
        pendingVisualCollapse?.cancel()
        pendingVisualCollapse = nil
    }

    private func launcherFrame(on screen: NSScreen) -> NSRect {
        WidgetPanelGeometry.frame(size: launcherSize, topRightAnchor: resolvedAnchor(on: screen))
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        WidgetPanelGeometry.frame(size: expandedSize, topRightAnchor: resolvedAnchor(on: screen))
    }

    private func resolvedAnchor(on screen: NSScreen) -> CGPoint {
        let fallbackFrame = WidgetPanelGeometry.topRightFrame(size: expandedSize, visibleFrame: screen.visibleFrame, inset: edgeInset)
        let requested = topRightAnchor ?? positionStore.load() ?? WidgetPanelGeometry.topRightAnchor(for: fallbackFrame)
        let clamped = WidgetPanelGeometry.clampedTopRightAnchor(requested, expandedSize: expandedSize, visibleFrame: screen.visibleFrame)
        topRightAnchor = clamped
        return clamped
    }

    /// Frame and SwiftUI mode change under one disabled screen flush. This keeps
    /// expanded content out of the launcher's 40-point clipping bounds and keeps
    /// the shared top-right edge stationary during every transition.
    private func applyGeometry(_ panel: NSPanel, visibility: WidgetHoverState.Visibility, notify: Bool) {
        let screen = panel.screen ?? preferredScreen()
        let frame = visibility == .expanded ? expandedFrame(on: screen) : launcherFrame(on: screen)
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: false, animate: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        if notify { notifyPresentationChanged() }
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }
    private func expand(_ panel: NSPanel) {
        cancelPendingVisualCollapse()
        applyGeometry(panel, visibility: .expanded, notify: true)
    }

    /// The SwiftUI surface folds back into the launcher while the hosting view
    /// keeps its full layout bounds. Only after that visual transition finishes
    /// do we atomically install the 40-point panel geometry.
    private func beginAnimatedCollapse(_ panel: NSPanel) {
        cancelPendingVisualCollapse()
        notifyPresentationChanged()
        let work = DispatchWorkItem { [weak self, weak panel] in
            Task { @MainActor in
                guard let self, let panel, self.hoverState.visibility == .launcher else { return }
                self.pendingVisualCollapse = nil
                self.applyGeometry(panel, visibility: .launcher, notify: false)
            }
        }
        pendingVisualCollapse = work
        DispatchQueue.main.asyncAfter(deadline: .now() + presentationDuration, execute: work)
    }

    private func notifyPresentationChanged() {
        NotificationCenter.default.post(name: .easyTODOWidgetPresentationChanged, object: hoverState.visibility)
    }

    private func preferredScreen() -> NSScreen {
        if let saved = topRightAnchor ?? positionStore.load(),
           let screen = NSScreen.screens.first(where: { $0.frame.contains(saved) }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    private func bestScreen(for frame: NSRect) -> NSScreen {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        } ?? preferredScreen()
    }
}

private final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { WidgetWindowManager.shared.activateForInteraction() }
        if event.type == .rightMouseDown {
            WidgetWindowManager.shared.showContextMenu(for: event, in: self)
            return
        }
        super.sendEvent(event)
    }
}

private final class WidgetTrackingHostingView<Content: View>: NSHostingView<Content> {
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        WidgetWindowManager.shared.pointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        WidgetWindowManager.shared.pointerExited()
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

@MainActor
private final class WidgetContextMenuController: NSObject {
    @objc func openMainApp() { WindowManager.shared.showMainWindow() }
    @objc func hideWidget() { WidgetWindowManager.shared.hideWidget() }
}
