import SwiftData
import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    @State private var newName = ""
    @State private var selectedColor = CategoryColor.blue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Categories").font(.title2.bold())
            List {
                ForEach(categories) { category in
                    CategoryManagementRow(category: category, onSave: save) {
                        modelContext.delete(category)
                        save()
                    }
                }
            }
            .frame(minHeight: 220)

            HStack {
                TextField("New category", text: $newName)
                CategoryColorControl(selection: $selectedColor)
                .frame(width: 110)
                Button("Add", action: addCategory)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Text("Deleting a category leaves its tasks uncategorized.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 390)
    }

    private func addCategory() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(TaskCategory(name: name, colorIdentifier: selectedColor.rawValue, sortOrder: categories.count))
        newName = ""
        save()
    }

    private func save() { try? modelContext.save() }
}

private struct CategoryManagementRow: View {
    @Bindable var category: TaskCategory
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Circle().fill(category.color.swiftUIColor).frame(width: 9, height: 9)
            TextField("Category name", text: $category.name)
                .onChange(of: category.name) { _, _ in onSave() }
            CategoryColorControl(selection: colorBinding).frame(width: 100)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).accessibilityLabel("Delete category")
        }
    }

    private var colorBinding: Binding<CategoryColor> {
        Binding(
            get: { category.color },
            set: { category.color = $0; onSave() }
        )
    }
}
