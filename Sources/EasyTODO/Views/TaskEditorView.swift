import SwiftData
import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    @Bindable var task: TodoTask

    @State private var hasDueDate = false
    @State private var hasDueTime = false
    @State private var dueDate = Date()

    var body: some View {
        Form {
            TextField("Task", text: $task.title)

            LabeledContent("Category") {
                CategorySelectionControl(categories: categories, selection: categoryBinding)
            }

            Toggle("Due date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                Toggle("Specific time", isOn: $hasDueTime)
                if hasDueTime {
                    DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                }
            }

            Toggle("Completed", isOn: completionBinding)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .onAppear {
            hasDueDate = task.scheduledDate != nil
            hasDueTime = task.hasExplicitDueTime
            dueDate = task.scheduledDate ?? .now
        }
    }

    private var categoryBinding: Binding<UUID?> {
        Binding(
            get: { task.category?.id },
            set: { id in task.category = categories.first { $0.id == id } }
        )
    }

    private var completionBinding: Binding<Bool> {
        Binding(get: { task.isCompleted }, set: { task.setCompleted($0) })
    }

    private func save() {
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.setDueDate(hasDueDate ? dueDate : nil, includesTime: hasDueDate && hasDueTime)
        try? modelContext.save()
        dismiss()
    }
}
