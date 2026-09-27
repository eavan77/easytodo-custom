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

    mutating func synchronizePointer(isInside: Bool) {
        if isInside { pointerEntered() }
        else { pointerExited() }
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

enum WidgetInteractionKind: Hashable {
    case menu
    case contextMenu
    case taskEditor
    case taskCreation
    case taskImport
    case categoryManagement
    case planUpdate
    case quickAdd
    case panelDrag
}

struct WidgetInteractionRegistry: Equatable {
    private(set) var active = Set<WidgetInteractionKind>()

    var count: Int { active.count }

    mutating func begin(_ kind: WidgetInteractionKind) -> Bool {
        active.insert(kind).inserted
    }

    mutating func end(_ kind: WidgetInteractionKind) -> Bool {
        active.remove(kind) != nil
    }

    mutating func reset() {
        active.removeAll()
    }
}
