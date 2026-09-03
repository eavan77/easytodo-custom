import SwiftData
import SwiftUI

struct TaskCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]

    var initialCategoryID: UUID?
    var onCreated: ((TodoTask) -> Void)?

    @State private var title = ""
    @State private var categoryID: UUID?
    @State private var hasDueDate = false
    @State private var hasDueTime = false
    @State private var dueDate = Date()
    @FocusState private var titleFocused: Bool

    var body: some View {
        Form {
            TextField("Task", text: $title)
                .focused($titleFocused)

            LabeledContent("Category") {
                CategorySelectionControl(categories: categories, selection: $categoryID)
            }

            Toggle("Due date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                Toggle("Add specific time", isOn: $hasDueTime)
                if hasDueTime {
                    DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add", action: createTask)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding(4)
        .frame(width: 360)
        .onAppear {
            categoryID = initialCategoryID
            titleFocused = true
        }
    }

    private func createTask() {
        do {
            let selectedDueDate = hasDueDate ? dueDate : nil
            guard let task = try TaskCreation.addTask(title: title, scheduledDate: nil, in: modelContext) else { return }
            task.category = categories.first { $0.id == categoryID }
            task.setDueDate(selectedDueDate, includesTime: hasDueDate && hasDueTime)
            try modelContext.save()
            onCreated?(task)
            dismiss()
        } catch {
            assertionFailure("Unable to create task: \(error)")
        }
    }
}
