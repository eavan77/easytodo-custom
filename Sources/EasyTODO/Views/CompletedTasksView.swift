import SwiftData
import SwiftUI

struct CompletedTasksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]

    private var completedTasks: [TodoTask] {
        tasks.filter(\.isCompleted).sorted {
            ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Completed").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if completedTasks.isEmpty {
                ContentUnavailableView("No completed tasks", systemImage: "checkmark.circle")
            } else {
                List(completedTasks) { task in
                    HStack {
                        Button { restore(task) } label: { Image(systemName: "checkmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Mark \(task.title) unfinished")
                        VStack(alignment: .leading) {
                            Text(task.title)
                            if let completedAt = task.completedAt {
                                Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(20).frame(width: 520, height: 420)
    }

    private func restore(_ task: TodoTask) {
        withAnimation { task.setCompleted(false) }
        try? modelContext.save()
    }
}
