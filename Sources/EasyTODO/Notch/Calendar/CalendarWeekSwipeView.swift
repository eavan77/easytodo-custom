import AppKit
import SwiftUI

// A single deliberate horizontal gesture changes at most one week. Vertical
// scrolling and momentum never navigate. Positive input means a left swipe.
struct CalendarWeekSwipeState {
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private(set) var horizontal: Bool?

    mutating func reset() { x = 0; y = 0; horizontal = nil }

    mutating func update(x deltaX: CGFloat, y deltaY: CGFloat) {
        x += deltaX
        y += deltaY
        if horizontal == nil, max(abs(x), abs(y)) >= 8 {
            horizontal = abs(x) > abs(y) * 1.5
        }
    }

    func completedStep() -> Int? {
        guard horizontal == true, abs(x) >= 50 else { return nil }
        return x > 0 ? 1 : -1
    }
}

struct CalendarWeekSwipeView: NSViewRepresentable {
    var onNavigate: (Int) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onNavigate = onNavigate
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) { view.onNavigate = onNavigate }

    static func dismantleNSView(_ view: SwipeView, coordinator: ()) { view.stop() }

    final class SwipeView: NSView {
        var onNavigate: ((Int) -> Void)?
        private var monitor: Any?
        private var gesture = CalendarWeekSwipeState()

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self else { return false }
                    return self.handle(event) == nil
                }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            gesture.reset()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window, window.attachedSheet == nil,
                  !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
            if event.type == .swipe {
                guard abs(event.deltaX) > abs(event.deltaY) else { return event }
                onNavigate?(event.deltaX > 0 ? 1 : -1)
                return nil
            }
            guard event.hasPreciseScrollingDeltas else { return event }
            if !event.momentumPhase.isEmpty { return gesture.horizontal == true ? nil : event }
            if event.phase.contains(.began) { gesture.reset() }
            if event.phase.contains(.cancelled) { gesture.reset(); return event }
            guard !event.phase.isEmpty else { return event }
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
            gesture.update(x: event.scrollingDeltaX * direction, y: event.scrollingDeltaY * direction)
            let handled = gesture.horizontal == true
            if event.phase.contains(.ended), let step = gesture.completedStep() {
                onNavigate?(step)
            }
            return handled ? nil : event
        }
    }
}
