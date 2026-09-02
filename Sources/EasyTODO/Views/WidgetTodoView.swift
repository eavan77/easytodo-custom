import Foundation
import SwiftData
import SwiftUI

struct WidgetRootView: View {
    @State private var visibility = WidgetWindowManager.shared.hoverState.visibility

    var body: some View {
        Group {
            if visibility != .expanded {
                Button {
                    WidgetWindowManager.shared.pointerEntered()
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open EasyTODO tasks")
                .modifier(WidgetGlassSurface(cornerRadius: 13, compact: true))
            } else {
                WidgetTodoView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOWidgetPresentationChanged)) { notification in
            if let newVisibility = notification.object as? WidgetHoverState.Visibility { visibility = newVisibility }
        }
    }
}

struct WidgetTodoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var tasks: [TodoTask]
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    @AppStorage(EasyTODOSettings.theme) private var theme = ThemeOption.light.rawValue
    @AppStorage(EasyTODOSettings.widgetCategoryFilter) private var storedFilter = "all"
    @State private var newTaskTitle = ""
    @State private var editingTask: TodoTask?
    @State private var isCreatingTask = false
    @FocusState private var quickAddFocused: Bool

    private var filter: TaskCategoryFilter { TaskCategoryFilter(storedValue: storedFilter) }
    private var visibleTasks: [TodoTask] { TaskUrgencyOrdering.visibleTasks(from: tasks, filter: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            quickAdd
            if visibleTasks.isEmpty { emptyState } else { taskList }
            footer
        }
        .padding(13).frame(width: 276)
        .foregroundStyle(.primary)
        .modifier(WidgetGlassSurface(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(count: 2) { WindowManager.shared.showMainWindow() }
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task)
                .onAppear { WidgetWindowManager.shared.beginChildInteraction() }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction() }
        }
        .sheet(isPresented: $isCreatingTask) {
            TaskCreationView(initialCategoryID: selectedCategoryID)
                .onAppear { WidgetWindowManager.shared.beginChildInteraction() }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction() }
        }
        .onChange(of: quickAddFocused) { _, focused in
            focused ? WidgetWindowManager.shared.beginChildInteraction() : WidgetWindowManager.shared.endChildInteraction()
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Up Next", systemImage: "checklist").font(.system(size: 14, weight: .semibold))
            Spacer()
            Picker("Category", selection: $storedFilter) {
                Text("All").tag("all")
                Text("Uncategorized").tag("uncategorized")
                ForEach(categories) { Text($0.name).tag($0.id.uuidString) }
            }
            .labelsHidden().frame(maxWidth: 128).accessibilityLabel("Filter by category")
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField("Add a task", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .focused($quickAddFocused)
                .onSubmit { addTask(); quickAddFocused = false }
            Button { isCreatingTask = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.plain).help("Add with category and due date").accessibilityLabel("Add task with details")
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(visibleTasks) { task in
                    taskRow(task).transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(maxHeight: 210).scrollIndicators(.visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: visibleTasks.map(\.isCompleted))
    }

    private func taskRow(_ task: TodoTask) -> some View {
        HStack(spacing: 8) {
            Button { complete(task) } label: { Image(systemName: "circle").font(.system(size: 14, weight: .semibold)) }
                .buttonStyle(.plain).accessibilityLabel("Mark \(task.title) complete")
            if let category = task.category {
                Circle().fill(category.color.swiftUIColor).frame(width: 7, height: 7)
                    .help(category.name).accessibilityLabel("Category: \(category.name)")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if let deadline = DeadlineFormatting.text(for: task) {
                    Text(deadline).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(taskIsOverdue(task) ? Color.orange : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            Button { editingTask = task } label: { Image(systemName: "ellipsis") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Edit \(task.title)")
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu { Button("Edit") { editingTask = task } }
    }

    private var emptyState: some View {
        ContentUnavailableView("Nothing pending", systemImage: "checkmark.circle", description: Text("Add a task or choose another category."))
            .frame(maxHeight: 150)
    }
    private var footer: some View {
        Button { WindowManager.shared.showMainWindow() } label: {
            Label("Open full app", systemImage: "arrow.up.right.square")
                .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
        }.buttonStyle(.plain).foregroundStyle(.secondary)
    }

    private func addTask() {
        do {
            guard let task = try TaskCreation.addTask(title: newTaskTitle, scheduledDate: nil, in: modelContext) else { return }
            if case let .category(id) = filter { task.category = categories.first { $0.id == id } }
            newTaskTitle = ""
            try modelContext.save()
        } catch { assertionFailure("Unable to add widget task: \(error)") }
    }
    private func complete(_ task: TodoTask) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { task.setCompleted(true) }
        try? modelContext.save()
        CompletionFeedbackPlayer.playTaskCompletedSound()
    }
    private func taskIsOverdue(_ task: TodoTask) -> Bool { (task.effectiveDeadline() ?? .distantFuture) < .now }
    private var selectedCategoryID: UUID? {
        if case let .category(id) = filter { return id }
        return nil
    }
    private var preferredColorScheme: ColorScheme? { (ThemeOption(rawValue: theme) ?? .light) == .light ? .light : .dark }
}

private struct WidgetGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    var compact = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(compact ? 0.08 : 0.12), radius: compact ? 5 : 16, y: compact ? 2 : 7)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
                }
                .shadow(color: .black.opacity(compact ? 0.08 : 0.14), radius: compact ? 5 : 14, y: compact ? 2 : 6)
        }
    }
}
