import AppKit
import SwiftData
import SwiftUI

@MainActor
final class WidgetWindowManager {
    static let shared = WidgetWindowManager()

    private var modelContainer: ModelContainer?
    private var widgetWindow: NSPanel?
    private var contextMenuController: WidgetContextMenuController?
    private var activationObservers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        activationObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetWindowManager.shared.updateOpacity(animated: true) }
            },
            center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in WidgetWindowManager.shared.updateOpacity(animated: true) }
            }
        ]
    }

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func showWidget() {
        guard let modelContainer else {
            NSLog("EasyTODO widget cannot open before SwiftData is configured.")
            WindowManager.shared.showMainWindow()
            return
        }

        if let widgetWindow {
            show(window: widgetWindow)
            return
        }

        let size = NSSize(width: 276, height: 350)
        let panel = WidgetPanel(
            contentRect: preferredFrame(size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.identifier = NSUserInterfaceItemIdentifier("easy-todo-widget-window")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.alphaValue = targetAlphaValue
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        let hostingController = NSHostingController(
            rootView: WidgetTodoView()
                .modelContainer(modelContainer)
        )
        hostingController.view.frame = NSRect(origin: .zero, size: size)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingController.view

        widgetWindow = panel
        show(window: panel)
    }

    func applyWidgetTransparency() {
        updateOpacity(animated: true)
    }

    func showContextMenu(for event: NSEvent, in panel: NSPanel) {
        let controller = WidgetContextMenuController()
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Main App", action: #selector(WidgetContextMenuController.openMainApp), keyEquivalent: "")
        openItem.target = controller
        menu.addItem(openItem)

        menu.addItem(.separator())
        menu.addItem(transparencyMenuItem(controller: controller))
        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "Close Widget", action: #selector(WidgetContextMenuController.closeWidget), keyEquivalent: "")
        closeItem.target = controller
        menu.addItem(closeItem)

        contextMenuController = controller
        menu.popUp(positioning: nil, at: event.locationInWindow, in: panel.contentView)
    }

    func toggleWidget() {
        if widgetWindow?.isVisible == true {
            closeWidget()
        } else {
            showWidget()
        }
    }

    func closeWidget() {
        widgetWindow?.orderOut(nil)
    }

    private func show(window: NSPanel) {
        window.alphaValue = targetAlphaValue

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.orderFrontRegardless()
    }

    fileprivate func activateForInteraction() {
        NSApp.activate(ignoringOtherApps: true)
        updateOpacity(animated: true)
    }

    fileprivate func updateOpacity(animated: Bool) {
        guard let widgetWindow else { return }
        let changes = { widgetWindow.alphaValue = self.targetAlphaValue }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { changes(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            widgetWindow.animator().alphaValue = targetAlphaValue
        }
    }

    private var targetAlphaValue: CGFloat {
        let key = NSApp.isActive ? EasyTODOSettings.widgetActiveOpacity : EasyTODOSettings.widgetInactiveOpacity
        let value = UserDefaults.standard.double(forKey: key)
        return CGFloat(min(max(value, 0.20), 1.0))
    }

    private func transparencyMenuItem(controller: WidgetContextMenuController) -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 54))
        let currentValue = UserDefaults.standard.double(forKey: EasyTODOSettings.widgetInactiveOpacity)

        let label = NSTextField(labelWithString: "Inactive opacity \(Int((currentValue * 100).rounded()))%")
        label.frame = NSRect(x: 14, y: 31, width: 190, height: 16)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor

        let slider = NSSlider(value: currentValue, minValue: 0.25, maxValue: 0.70, target: controller, action: #selector(WidgetContextMenuController.changeTransparency(_:)))
        slider.frame = NSRect(x: 12, y: 6, width: 196, height: 24)
        slider.isContinuous = true

        controller.transparencyLabel = label
        container.addSubview(label)
        container.addSubview(slider)
        item.view = container

        return item
    }

    private func preferredFrame(size: NSSize) -> NSRect {
        let visibleFrame = preferredScreen().visibleFrame
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.maxY - size.height - margin
        )

        return NSRect(origin: origin, size: size)
    }

    private func preferredScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            WidgetWindowManager.shared.activateForInteraction()
        }
        if event.type == .rightMouseDown {
            WidgetWindowManager.shared.showContextMenu(for: event, in: self)
            return
        }

        super.sendEvent(event)
    }
}

@MainActor
private final class WidgetContextMenuController: NSObject {
    weak var transparencyLabel: NSTextField?

    @objc func openMainApp() {
        WindowManager.shared.showMainWindow()
    }

    @objc func closeWidget() {
        WidgetWindowManager.shared.closeWidget()
    }

    @objc func changeTransparency(_ sender: NSSlider) {
        let value = sender.doubleValue
        UserDefaults.standard.set(value, forKey: EasyTODOSettings.widgetInactiveOpacity)
        transparencyLabel?.stringValue = "Inactive opacity \(Int((value * 100).rounded()))%"
        WidgetWindowManager.shared.applyWidgetTransparency()
    }
}
