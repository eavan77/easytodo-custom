import SwiftData
import SwiftUI

struct TaskBlockDefinitionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var definition: TaskBlockDefinition
    let canDelete: Bool
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSave: () -> Void

    var body: some View {
        Form {
            TextField("Block name", text: $definition.title)
            TextField("Estimated time (blank = Auto)", text: optionalInteger($definition.estimatedMinutes))
            Toggle("Can split into sessions", isOn: $definition.splittable)
            if definition.splittable {
                TextField("Minimum session (blank = Auto)", text: optionalInteger($definition.minimumSessionMinutes))
            }
            HStack {
                Button("Duplicate") { onDuplicate(); onSave(); dismiss() }
                if canDelete { Button("Delete", role: .destructive) { onDelete(); onSave(); dismiss() } }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { definition.updatedAt = .now; onSave(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(definition.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.formStyle(.grouped).frame(width: 390, height: 260)
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(get: { value.wrappedValue.map(String.init) ?? "" }, set: {
            value.wrappedValue = Int($0).flatMap { $0 > 0 ? $0 : nil }
        })
    }
}
