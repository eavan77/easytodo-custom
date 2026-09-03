import AppKit
import Foundation
import SwiftData
import SwiftUI

struct WidgetRootView: View {
    @State private var visibility = WidgetWindowManager.shared.hoverState.visibility
    @State private var corner = WidgetWindowManager.shared.currentCorner
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: corner.alignment) {
            if visibility != .expanded {
                Button {
                    WidgetWindowManager.shared.pointerEntered()
                } label: {
                    SimpleLauncherView()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open EasyTODO tasks")
                .modifier(WidgetGlassSurface(cornerRadius: 20, compact: true))
                .transition(.opacity.combined(with: .scale(scale: 0.72, anchor: corner.unitPoint)))
            } else {
                WidgetTodoView()
                    .transition(.opacity.combined(with: .scale(scale: 0.78, anchor: corner.unitPoint)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.88), value: visibility)
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOWidgetPresentationChanged)) { notification in
            if let newVisibility = notification.object as? WidgetHoverState.Visibility { visibility = newVisibility }
            corner = WidgetWindowManager.shared.currentCorner
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
    @State private var isManagingCategories = false
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
        .padding(13).frame(width: 276, height: 350, alignment: .top)
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
        .sheet(isPresented: $isManagingCategories) {
            CategoryManagementView()
                .onAppear { WidgetWindowManager.shared.beginChildInteraction() }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction() }
        }
        .onChange(of: quickAddFocused) { _, focused in
            focused ? WidgetWindowManager.shared.beginChildInteraction() : WidgetWindowManager.shared.endChildInteraction()
        }
        .onChange(of: categories.map(\.id)) { _, categoryIDs in
            if case let .category(id) = filter, !categoryIDs.contains(id) {
                storedFilter = "all"
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            WidgetDragHandle()
                .frame(width: 24, height: 18)
                .help("Drag widget")
                .accessibilityLabel("Drag widget")
            Label("Up Next", systemImage: "checklist").font(.system(size: 14, weight: .semibold))
            Spacer()
            CategoryFilterControl(categories: categories, storedFilter: $storedFilter)
                .frame(maxWidth: 82)
            Button { isManagingCategories = true } label: {
                Image(systemName: "tag")
            }
            .buttonStyle(.plain)
            .help("Manage categories")
            .accessibilityLabel("Manage categories")
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
            Menu {
                Button("Edit", systemImage: "pencil") { editingTask = task }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { delete(task) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Actions for \(task.title)")
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editingTask = task }
            Button("Delete", systemImage: "trash", role: .destructive) { delete(task) }
        }
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
    private func delete(_ task: TodoTask) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            modelContext.delete(task)
        }
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to delete widget task: \(error)")
        }
    }
    private func taskIsOverdue(_ task: TodoTask) -> Bool { (task.effectiveDeadline() ?? .distantFuture) < .now }
    private var selectedCategoryID: UUID? {
        if case let .category(id) = filter { return id }
        return nil
    }
    private var preferredColorScheme: ColorScheme? { (ThemeOption(rawValue: theme) ?? .light) == .light ? .light : .dark }
}

private struct SimpleLauncherView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.10))

            Image(systemName: "checklist.checked")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .overlay {
            Circle()
                .stroke(Color(red: 1.0, green: 0.76, blue: 0.84).opacity(0.92), lineWidth: 1.25)
                .shadow(color: Color(red: 1.0, green: 0.74, blue: 0.83).opacity(0.34), radius: 1.5)
                .padding(1)
        }
        .clipShape(Circle())
        .frame(width: 40, height: 40)
        .contentShape(Circle())
    }
}

private struct WidgetGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    var compact = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if compact {
                content.glassEffect(.regular, in: .circle)
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 7)
            }
        } else {
            if compact {
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
            } else {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            }
        }
    }
}

private struct WidgetDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WidgetDragHandleNSView {
        WidgetDragHandleNSView()
    }

    func updateNSView(_ nsView: WidgetDragHandleNSView, context: Context) {}
}

private final class WidgetDragHandleNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? NSPanel else { return }
        WidgetWindowManager.shared.performRealPanelDrag(panel, mouseDownEvent: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bar = NSBezierPath(roundedRect: NSRect(x: 4, y: bounds.midY - 1, width: max(8, bounds.width - 8), height: 2), xRadius: 1, yRadius: 1)
        NSColor.secondaryLabelColor.withAlphaComponent(0.42).setFill()
        bar.fill()
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .handle }
    override func accessibilityLabel() -> String? { "Drag widget" }
}

private extension WidgetCorner {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}
