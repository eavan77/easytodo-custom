@preconcurrency import AppKit
import SwiftData
import SwiftUI

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]

    @AppStorage(EasyTODOSettings.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(EasyTODOSettings.hiddenDockIcon) private var hiddenDockIcon = false
    @AppStorage(EasyTODOSettings.showMenuBar) private var showMenuBar = true
    @AppStorage(EasyTODOSettings.transparency) private var transparency = 0.80
    @AppStorage(EasyTODOSettings.widgetCategoryFilter) private var storedFilter = "all"

    @State private var isCreatingTask = false
    @State private var isCategoriesPresented = false
    @State private var isCompletedHistoryPresented = false
    @State private var deletedTaskToRestore: DeletedTaskSnapshot?
    @State private var undoKeyMonitor: Any?
    @State private var fireworksTrigger = 0

    private var filter: TaskCategoryFilter { TaskCategoryFilter(storedValue: storedFilter) }
    private var displayedTasks: [TodoTask] { TaskUrgencyOrdering.visibleTasks(from: tasks, filter: filter) }

    var body: some View {
        ZStack {
            neutralSurface
            VStack(spacing: 0) {
                header
                Divider().padding(.horizontal, 14)
                taskList
            }
            CompletionFireworksView(trigger: fireworksTrigger)
        }
        .frame(minWidth: 310, idealWidth: 380, minHeight: 340, idealHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(WindowAccessor { WindowManager.shared.configureMainWindow($0) })
        .contextMenu { windowContextMenu }
        .sheet(isPresented: $isCreatingTask) {
            TaskCreationView(initialCategoryID: selectedCategoryID)
        }
        .sheet(isPresented: $isCategoriesPresented) { CategoryManagementView() }
        .sheet(isPresented: $isCompletedHistoryPresented) { CompletedTasksView() }
        .onAppear {
            installUndoDeleteKeyboardMonitor()
            WindowManager.shared.applyWindowSettings()
            WindowManager.shared.applyActivationPolicy()
        }
        .onDisappear { removeUndoDeleteKeyboardMonitor() }
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOFocusNewTask)) { _ in
            WindowManager.shared.showMainWindow()
            isCreatingTask = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOUndoDeleteTask)) { _ in undoLastDeletedTask() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in saveChanges() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in saveChanges() }
        .onChange(of: alwaysOnTop) { _, _ in WindowManager.shared.applyWindowSettings() }
        .onChange(of: transparency) { _, _ in WindowManager.shared.applyWindowSettings() }
        .onChange(of: hiddenDockIcon) { _, _ in WindowManager.shared.applyActivationPolicy() }
        .onChange(of: showMenuBar) { _, _ in WindowManager.shared.applyActivationPolicy() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tasks").font(.system(size: 19, weight: .semibold))
                    Text("\(displayedTasks.count) pending").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                iconButton("minus", label: "Minimize") { WindowManager.shared.minimizeMainWindow() }
                iconButton("clock.arrow.circlepath", label: "Completed task history") { isCompletedHistoryPresented = true }
                iconButton("tag", label: "Manage categories") { isCategoriesPresented = true }
                iconButton("plus", label: "Add task") { isCreatingTask = true }
            }
            HStack {
                Picker("Category", selection: $storedFilter) {
                    Text("All").tag("all")
                    Text("Uncategorized").tag("uncategorized")
                    ForEach(categories) { Text($0.name).tag($0.id.uuidString) }
                }
                .frame(maxWidth: 210).accessibilityLabel("Filter tasks by category")
                Spacer()
                Button { WidgetWindowManager.shared.showWidget() } label: {
                    Label("Floating Widget", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var taskList: some View {
        List {
            if displayedTasks.isEmpty {
                ContentUnavailableView("No pending tasks", systemImage: "checkmark.circle", description: Text("Add a task to get started."))
                    .frame(maxWidth: .infinity).padding(.vertical, 42)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(displayedTasks) { task in
                TaskRow(task: task, onUpdate: saveChanges, onCompletionChanged: handleCompletionChange) {
                    delete(task)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 10))
                .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
    }

    private var neutralSurface: some View {
        Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.18))
            .contentShape(Rectangle())
    }

    @ViewBuilder private var windowContextMenu: some View {
        Button { WindowManager.shared.closeMainWindow() } label: { Label("Close Window", systemImage: "xmark") }
        Button { WindowManager.shared.minimizeMainWindow() } label: { Label("Minimize Window", systemImage: "minus") }
        Button { WidgetWindowManager.shared.showWidget(); WindowManager.shared.closeMainWindow() } label: {
            Label("Change to Widget", systemImage: "rectangle.on.rectangle")
        }
        Divider()
        Button { alwaysOnTop.toggle(); WindowManager.shared.applyWindowSettings() } label: {
            Label("Always on Top", systemImage: alwaysOnTop ? "checkmark.circle.fill" : "circle")
        }
        if deletedTaskToRestore != nil {
            Divider()
            Button { undoLastDeletedTask() } label: { Label("Undo Delete", systemImage: "arrow.uturn.backward") }
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }

    private var selectedCategoryID: UUID? {
        if case let .category(id) = filter { return id }
        return nil
    }

    private func handleCompletionChange(task: TodoTask, oldValue: Bool, newValue: Bool) {
        task.completedAt = newValue ? .now : nil
        saveChanges()
        guard !oldValue && newValue else { return }
        CompletionFeedbackPlayer.playTaskCompletedSound()
        fireworksTrigger += 1
    }

    private func delete(_ task: TodoTask) {
        deletedTaskToRestore = DeletedTaskSnapshot(task: task)
        modelContext.delete(task)
        saveChanges()
    }

    private func undoLastDeletedTask() {
        guard let snapshot = deletedTaskToRestore else { return }
        modelContext.insert(snapshot.task())
        deletedTaskToRestore = nil
        saveChanges()
    }

    private func installUndoDeleteKeyboardMonitor() {
        guard undoKeyMonitor == nil else { return }
        undoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.charactersIgnoringModifiers?.lowercased() == "z",
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control),
                  deletedTaskToRestore != nil else { return event }
            undoLastDeletedTask()
            return nil
        }
    }

    private func removeUndoDeleteKeyboardMonitor() {
        guard let undoKeyMonitor else { return }
        NSEvent.removeMonitor(undoKeyMonitor)
        self.undoKeyMonitor = nil
    }

    private func saveChanges() {
        do { try modelContext.save() }
        catch { assertionFailure("Unable to save tasks: \(error)") }
    }
}

private struct DeletedTaskSnapshot {
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
    let scheduledDate: Date?
    let hasExplicitDueTime: Bool
    let completedAt: Date?
    let category: TaskCategory?
    let priority: TaskPriority
    let repeatRule: TaskRepeatRule
    let recurrenceGroupID: String?

    init(task: TodoTask) {
        title = task.title; isCompleted = task.isCompleted; sortOrder = task.sortOrder; createdAt = task.createdAt
        scheduledDate = task.scheduledDate; hasExplicitDueTime = task.hasExplicitDueTime; completedAt = task.completedAt
        category = task.category; priority = task.priority; repeatRule = task.repeatRule; recurrenceGroupID = task.recurrenceGroupID
    }

    func task() -> TodoTask {
        TodoTask(title: title, isCompleted: isCompleted, sortOrder: sortOrder, createdAt: createdAt,
                 scheduledDate: scheduledDate, hasExplicitDueTime: hasExplicitDueTime, completedAt: completedAt,
                 category: category, priority: priority, repeatRule: repeatRule, recurrenceGroupID: recurrenceGroupID)
    }
}
