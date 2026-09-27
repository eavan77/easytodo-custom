import SwiftUI

struct AddTaskBar: View {
    @Binding var title: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onNewTask: () -> Void
    var onPasteTasks: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            TextField("Add a task", text: $title)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(onSubmit)

            Menu {
                Button("New task", systemImage: "square.and.pencil", action: onNewTask)
                Button("Paste tasks", systemImage: "doc.on.clipboard", action: onPasteTasks)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Paste or import tasks")
            .accessibilityLabel("Paste or import tasks")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
