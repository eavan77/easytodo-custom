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
        applyLauncherFrame(to: panel, animate: false)
        notifyPresentationChanged()
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
            applyExpandedFrame(to: panel, animate: true)
            notifyPresentationChanged()
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
        applyLauncherFrame(to: panel, animate: true)
        notifyPresentationChanged()
    }

    private func cancelPendingCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
    }

    private func applyLauncherFrame(to panel: NSPanel, animate: Bool) {
        let screen = panel.screen ?? preferredScreen()
        setFrame(launcherFrame(on: screen), on: panel, animate: animate)
    }

    private func applyExpandedFrame(to panel: NSPanel, animate: Bool) {
        let screen = panel.screen ?? preferredScreen()
        setFrame(expandedFrame(on: screen), on: panel, animate: animate)
    }

    private func launcherFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - launcherSize.width - edgeInset,
            y: visible.maxY - launcherSize.height - edgeInset,
            width: launcherSize.width,
            height: launcherSize.height
        )
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let launcher = launcherFrame(on: screen)
        return NSRect(
            x: launcher.maxX - expandedSize.width,
            y: launcher.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    private func setFrame(_ frame: NSRect, on panel: NSPanel, animate: Bool) {
        panel.setFrame(frame, display: true, animate: animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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
