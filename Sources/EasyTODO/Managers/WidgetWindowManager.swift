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
    private var pendingExpansion: DispatchWorkItem?
    private var menuObservers: [NSObjectProtocol] = []
    private var panelOwnership = WidgetPanelOwnershipState()
    private(set) var hoverState = WidgetHoverState()
    private(set) var currentCorner: WidgetCorner
    private let cornerStore: WidgetCornerStore

    private let expandedSize = NSSize(width: 276, height: 350)
    private let launcherSize = NSSize(width: 40, height: 40)
    private let edgeInset: CGFloat = 16
    private let collapseDelay = 0.45
    private let expansionDelay = 0.20
    private let presentationDuration = 0.28
    private let snapDuration = 0.22

    private init() {
        let store = WidgetCornerStore()
        cornerStore = store
        currentCorner = store.load() ?? .topRight
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

    /// Shows the launcher at its persisted corner. Hovering expands the same panel.
    func showWidget() {
        guard let modelContainer else {
            NSLog("EasyTODO widget cannot open before SwiftData is configured.")
            return
        }

        if widgetWindow == nil, panelOwnership.requestCreation() {
            createPanel(modelContainer: modelContainer)
        }

        guard let panel = widgetWindow else { return }
        assert(NSApp.windows.filter { $0.identifier?.rawValue == "easy-todo-widget-window" }.count <= 1)
        if hoverState.visibility != .hidden {
            panel.orderFrontRegardless()
            return
        }
        cancelPendingCollapse()
        cancelPendingVisualCollapse()
        cancelPendingExpansion()
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
        cancelPendingExpansion()
        hoverState.hide()
        notifyPresentationChanged()
        widgetWindow?.orderOut(nil)
    }

    func pointerEntered() {
        guard hoverState.visibility != .hidden else { return }
        cancelPendingCollapse()
        if hoverState.visibility == .launcher {
            scheduleExpansion()
        } else {
            hoverState.pointerEntered()
        }
    }

    func pointerExited() {
        cancelPendingExpansion()
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

    func performRealPanelDrag(_ panel: NSPanel, mouseDownEvent: NSEvent) {
        guard panel === widgetWindow, hoverState.visibility == .expanded else { return }
        cancelPendingExpansion()
        beginChildInteraction()
        panel.performDrag(with: mouseDownEvent)
        finishRealPanelDrag(panel) { [weak self] in
            self?.endChildInteraction()
        }
    }

    private func finishRealPanelDrag(_ panel: NSPanel, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let actualFrame = panel.frame
        let center = CGPoint(x: actualFrame.midX, y: actualFrame.midY)
        let screen = screenContainingCenter(of: panel.frame)
        let visibleFrame = screen.visibleFrame
        let selectedCorner = WidgetCorner.quadrant(containing: center, in: visibleFrame)
        currentCorner = selectedCorner
        cornerStore.save(selectedCorner)
        notifyPresentationChanged()
        let target = WidgetPanelGeometry.frame(
            size: expandedSize,
            corner: selectedCorner,
            visibleFrame: visibleFrame,
            inset: edgeInset
        )
        let persistedCorner = cornerStore.load()?.rawValue ?? "nil"
        NSLog("[WidgetDrag] frame=\(NSStringFromRect(actualFrame)) center={\(center.x), \(center.y)} visibleFrame=\(NSStringFromRect(visibleFrame)) mid={\(visibleFrame.midX), \(visibleFrame.midY)} corner=\(selectedCorner.rawValue) target=\(NSStringFromRect(target)) persisted=\(persistedCorner)")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = snapDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: {
            Task { @MainActor in
                assert(panel.frame.equalTo(target))
                completion?()
            }
        }
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
        panel.isMovable = true
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

    private func scheduleExpansion() {
        cancelPendingExpansion()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.hoverState.visibility == .launcher else { return }
                self.pendingExpansion = nil
                self.hoverState.pointerEntered()
                if let panel = self.widgetWindow { self.expand(panel) }
            }
        }
        pendingExpansion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + expansionDelay, execute: work)
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
    private func cancelPendingExpansion() {
        pendingExpansion?.cancel()
        pendingExpansion = nil
    }

    private func launcherFrame(on screen: NSScreen) -> NSRect {
        WidgetPanelGeometry.frame(size: launcherSize, corner: currentCorner, visibleFrame: screen.visibleFrame, inset: edgeInset)
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        WidgetPanelGeometry.frame(size: expandedSize, corner: currentCorner, visibleFrame: screen.visibleFrame, inset: edgeInset)
    }

    private func frame(for visibility: WidgetHoverState.Visibility, on screen: NSScreen) -> NSRect {
        visibility == .expanded ? expandedFrame(on: screen) : launcherFrame(on: screen)
    }

    /// Frame and SwiftUI mode change under one disabled screen flush. This keeps
    /// expanded content out of the launcher's 40-point clipping bounds and keeps
    /// the selected corner stationary during every transition.
    private func applyGeometry(_ panel: NSPanel, visibility: WidgetHoverState.Visibility, notify: Bool) {
        let screen = panel.screen ?? preferredScreen()
        let frame = frame(for: visibility, on: screen)
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
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func bestScreen(for frame: NSRect) -> NSScreen {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        } ?? preferredScreen()
    }


    private func screenContainingCenter(of frame: NSRect) -> NSScreen {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? bestScreen(for: frame)
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
