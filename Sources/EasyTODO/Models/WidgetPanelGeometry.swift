import CoreGraphics

enum WidgetPanelGeometry {
    static func draggedFrame(
        startingFrame: CGRect,
        startingMouseLocation: CGPoint,
        currentMouseLocation: CGPoint
    ) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: startingFrame.origin.x + currentMouseLocation.x - startingMouseLocation.x,
                y: startingFrame.origin.y + currentMouseLocation.y - startingMouseLocation.y
            ),
            size: startingFrame.size
        )
    }

    static func frame(
        size: CGSize,
        corner: WidgetCorner,
        visibleFrame: CGRect,
        inset: CGFloat
    ) -> CGRect {
        let x: CGFloat
        let y: CGFloat

        switch corner {
        case .topLeft, .bottomLeft:
            x = visibleFrame.minX + inset
        case .topRight, .bottomRight:
            x = visibleFrame.maxX - size.width - inset
        }

        switch corner {
        case .topLeft, .topRight:
            y = visibleFrame.maxY - size.height - inset
        case .bottomLeft, .bottomRight:
            y = visibleFrame.minY + inset
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

}
