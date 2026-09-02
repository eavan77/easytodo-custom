enum WidgetPresentationState: Equatable {
    case expanded
    case collapsed
    case hidden

    mutating func collapse() { self = .collapsed }
    mutating func expand() { self = .expanded }
    mutating func hide() { self = .hidden }
}
