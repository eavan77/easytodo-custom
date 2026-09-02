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
    private var menuObservers: [NSObjectProtocol] = []
    private(set) var hoverState = WidgetHoverState()

    private let expandedSize = NSSize(width: 276, height: 350)
    private let launcherSize = NSSize(width: 40, height: 40)
    private let edgeInset: CGFloat = 16
    private let collapseDelay = 0.45

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
        hoverState.show()
        transition(panel, to: .launcher)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func toggleWidget() {
        hoverState.visibility == .hidden ? showWidget() : hideWidget()
    }

    func hideWidget() {
        cancelPendingCollapse()
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
            transition(panel, to: .expanded)
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
        transition(panel, to: .launcher)
    }

    private func cancelPendingCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }

    private func launcherFrame(on screen: NSScreen) -> NSRect {
        WidgetPanelGeometry.topRightFrame(size: launcherSize, visibleFrame: screen.visibleFrame, inset: edgeInset)
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        WidgetPanelGeometry.topRightFrame(size: expandedSize, visibleFrame: screen.visibleFrame, inset: edgeInset)
    }

    /// Frame and SwiftUI mode change under one disabled screen flush. This keeps
    /// expanded content out of the launcher's 40-point clipping bounds and keeps
    /// the shared top-right edge stationary during every transition.
    private func transition(_ panel: NSPanel, to visibility: WidgetHoverState.Visibility) {
        let screen = panel.screen ?? preferredScreen()
        let frame = visibility == .expanded ? expandedFrame(on: screen) : launcherFrame(on: screen)
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: false, animate: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        notifyPresentationChanged()
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    private func notifyPresentationChanged() {
        NotificationCenter.default.post(name: .easyTODOWidgetPresentationChanged, object: hoverState.visibility)
    }

    private func preferredScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
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

@MainActor
private final class WidgetContextMenuController: NSObject {
    @objc func openMainApp() { WindowManager.shared.showMainWindow() }
    @objc func hideWidget() { WidgetWindowManager.shared.hideWidget() }
}
