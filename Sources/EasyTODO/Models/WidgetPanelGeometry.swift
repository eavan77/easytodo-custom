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
}
