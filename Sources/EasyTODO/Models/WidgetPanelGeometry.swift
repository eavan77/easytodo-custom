import CoreGraphics

enum WidgetPanelGeometry {
    static func topRightFrame(size: CGSize, visibleFrame: CGRect, inset: CGFloat) -> CGRect {
        CGRect(
            x: visibleFrame.maxX - size.width - inset,
            y: visibleFrame.maxY - size.height - inset,
            width: size.width,
            height: size.height
        )
    }

    static func frame(size: CGSize, topRightAnchor: CGPoint) -> CGRect {
        CGRect(
            x: topRightAnchor.x - size.width,
            y: topRightAnchor.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func topRightAnchor(for frame: CGRect) -> CGPoint {
        CGPoint(x: frame.maxX, y: frame.maxY)
    }

    /// Keeps the entire expanded widget visible. The launcher and expanded
    /// panel can then share this exact anchor without accumulating drift.
    static func clampedTopRightAnchor(
        _ anchor: CGPoint,
        expandedSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(anchor.x, visibleFrame.minX + expandedSize.width), visibleFrame.maxX),
            y: min(max(anchor.y, visibleFrame.minY + expandedSize.height), visibleFrame.maxY)
        )
    }

    static func clampedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let anchor = clampedTopRightAnchor(
            topRightAnchor(for: frame),
            expandedSize: frame.size,
            visibleFrame: visibleFrame
        )
        return self.frame(size: frame.size, topRightAnchor: anchor)
    }
}
