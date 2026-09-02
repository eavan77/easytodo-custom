struct WidgetHoverState: Equatable {
    enum Visibility: Equatable {
        case hidden
        case launcher
        case expanded
    }

    private(set) var visibility: Visibility = .hidden
    private(set) var isPointerInside = false
    private(set) var interactionLockCount = 0
    private(set) var isCollapsePending = false

    mutating func show() {
        visibility = .launcher
        isPointerInside = false
        interactionLockCount = 0
        isCollapsePending = false
    }

    mutating func hide() {
        visibility = .hidden
        isPointerInside = false
        interactionLockCount = 0
        isCollapsePending = false
    }

    mutating func pointerEntered() {
        guard visibility != .hidden else { return }
        isPointerInside = true
        isCollapsePending = false
        visibility = .expanded
    }

    mutating func pointerExited() {
        isPointerInside = false
        isCollapsePending = visibility == .expanded && interactionLockCount == 0
    }

    mutating func beginInteraction() {
        interactionLockCount += 1
        isCollapsePending = false
    }

    mutating func endInteraction() {
        interactionLockCount = max(0, interactionLockCount - 1)
        isCollapsePending = visibility == .expanded && !isPointerInside && interactionLockCount == 0
    }

    mutating func collapseGracePeriodCompleted() {
        guard isCollapsePending, !isPointerInside, interactionLockCount == 0 else { return }
        visibility = .launcher
        isCollapsePending = false
    }
}
