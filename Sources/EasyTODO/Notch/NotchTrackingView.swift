import AppKit
import SwiftData
import SwiftUI

final class NotchTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var hubHostingView: NSHostingView<AnyView>?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(area)
        trackingArea = area
    }

    override func layout() {
        super.layout()
        hubHostingView?.frame = bounds
    }

    func installHub(modelContainer: ModelContainer) {
        guard hubHostingView == nil else { return }

        let rootView = AnyView(
            HubView()
                .modelContainer(modelContainer)
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.isHidden = true

        addSubview(hostingView)
        hubHostingView = hostingView
    }

    func setHubVisible(_ visible: Bool) {
        hubHostingView?.isHidden = !visible
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
