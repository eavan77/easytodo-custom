import SwiftUI

struct CategorySelectionControl: View {
    let categories: [TaskCategory]
    @Binding var selection: UUID?

    private var selectedCategory: TaskCategory? {
        categories.first { $0.id == selection }
    }

    var body: some View {
        Menu {
            Button { selection = nil } label: {
                Text("None")
            }
            Divider()
            ForEach(categories) { category in
                Button { selection = category.id } label: {
                    HStack {
                        Circle().fill(category.color.swiftUIColor).frame(width: 9, height: 9)
                        Text(category.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let selectedCategory {
                    Circle().fill(selectedCategory.color.swiftUIColor).frame(width: 9, height: 9)
                    Text(selectedCategory.name)
                } else {
                    Text("None")
                }
            }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Category")
    }
}

struct CategoryColorControl: View {
    @Binding var selection: CategoryColor

    var body: some View {
        Menu {
            ForEach(CategoryColor.allCases) { color in
                Button { selection = color } label: {
                    HStack {
                        Circle().fill(color.swiftUIColor).frame(width: 9, height: 9)
                        Text(color.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(selection.swiftUIColor).frame(width: 9, height: 9)
                Text(selection.title)
            }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Category color: \(selection.title)")
    }
}

struct CategoryFilterControl: View {
    let categories: [TaskCategory]
    @Binding var storedFilter: String

    private var filter: TaskCategoryFilter { TaskCategoryFilter(storedValue: storedFilter) }
    private var selectedCategory: TaskCategory? {
        guard case let .category(id) = filter else { return nil }
        return categories.first { $0.id == id }
    }

    var body: some View {
        Menu {
            Button("All") { storedFilter = "all" }
            Button("Uncategorized") { storedFilter = "uncategorized" }
            Divider()
            ForEach(categories) { category in
                Button { storedFilter = category.id.uuidString } label: {
                    HStack {
                        Circle().fill(category.color.swiftUIColor).frame(width: 8, height: 8)
                        Text(category.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let selectedCategory {
                    Circle().fill(selectedCategory.color.swiftUIColor).frame(width: 8, height: 8)
                    Text(selectedCategory.name).lineLimit(1)
                } else {
                    Text(storedFilter == "uncategorized" ? "Uncategorized" : "All")
                }
            }
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Filter by category")
    }
}
