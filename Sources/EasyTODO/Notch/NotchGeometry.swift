import AppKit

struct NotchGeometry {
    let screen: NSScreen
    let collapsedFrame: NSRect

    private let expandedWidth: CGFloat = 460
    private let expandedHeight: CGFloat = 300

    init?(screen: NSScreen) {
        guard
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea,
            screen.safeAreaInsets.top > 0
        else {
            return nil
        }

        let notchLeft = leftArea.maxX
        let notchRight = rightArea.minX
        let notchWidth = notchRight - notchLeft

        guard notchWidth > 0 else {
            return nil
        }

        collapsedFrame = NSRect(
            x: notchLeft,
            y: screen.frame.maxY - screen.safeAreaInsets.top,
            width: notchWidth,
            height: screen.safeAreaInsets.top
        )

        self.screen = screen
    }

    var expandedFrame: NSRect {
        NSRect(
            x: collapsedFrame.midX - expandedWidth / 2,
            y: screen.frame.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )
    }

    static var builtIn: NotchGeometry? {
        guard let screen = NSScreen.screens.first(where: {
            $0.safeAreaInsets.top > 0 &&
            $0.auxiliaryTopLeftArea != nil &&
            $0.auxiliaryTopRightArea != nil
        }) else {
            return nil
        }

        return NotchGeometry(screen: screen)
    }
}
