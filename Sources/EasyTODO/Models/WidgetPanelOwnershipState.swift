struct WidgetPanelOwnershipState {
    private(set) var hasPanel = false

    mutating func requestCreation() -> Bool {
        guard !hasPanel else { return false }
        hasPanel = true
        return true
    }
}
