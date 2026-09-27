@preconcurrency import AppKit
import SwiftData
import SwiftUI

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    @Query private var workBlocks: [WorkBlock]
    @Query(sort: \DayCapacityTemplate.weekday) private var capacityTemplates: [DayCapacityTemplate]

    @AppStorage(EasyTODOSettings.alwaysOnTop) private var alwaysOnTop = true
    @AppStorage(EasyTODOSettings.hiddenDockIcon) private var hiddenDockIcon = false
    @AppStorage(EasyTODOSettings.showMenuBar) private var showMenuBar = true
    @AppStorage(EasyTODOSettings.transparency) private var transparency = 0.80
    @AppStorage(EasyTODOSettings.widgetCategoryFilter) private var storedFilter = "all"

    @State private var isCreatingTask = false
    @State private var isImportingTasks = false
    @State private var isCategoriesPresented = false
    @State private var isCompletedHistoryPresented = false
    @State private var deletedTaskToRestore: DeletedTaskSnapshot?
    @State private var undoKeyMonitor: Any?
    @State private var fireworksTrigger = 0
    @State private var selectedView: PlannerMainView = .focus
    @State private var planSort: TaskPlanSort = .plan
    @State private var appliedPlan: AppliedPlan?
    @State private var isPlanUpdatePresented = false
    @State private var plannerError: String?

    private var filter: TaskCategoryFilter { TaskCategoryFilter(storedValue: storedFilter) }
    private var displayedTasks: [TodoTask] {
        let visible = TaskUrgencyOrdering.visibleTasks(from: tasks, filter: filter)
        switch planSort {
        case .due: return visible
        case .plan: return visible.sorted { ($0.executionRank ?? Int.max) < ($1.executionRank ?? Int.max) }
        case .project:
            return visible.sorted {
                let left = $0.category?.name ?? "~", right = $1.category?.name ?? "~"
                if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
                return ($0.executionRank ?? Int.max) < ($1.executionRank ?? Int.max)
            }
        }
    }

    var body: some View {
        ZStack {
            neutralSurface
            VStack(spacing: 0) {
                header
                Divider().padding(.horizontal, 14)
                plannerContent
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
        .sheet(isPresented: $isImportingTasks) {
            PasteTasksView { plan in self.appliedPlan = plan }
        }
        .sheet(isPresented: $isCategoriesPresented) { CategoryManagementView() }
        .sheet(isPresented: $isCompletedHistoryPresented) { CompletedTasksView() }
        .sheet(isPresented: $isPlanUpdatePresented) {
            if let appliedPlan {
                PlanUpdateView(plan: appliedPlan, onUndo: undoLastPlan) { updated in
                    self.appliedPlan = updated
                }
            }
        }
        .alert("Unable to Replan", isPresented: Binding(get: { plannerError != nil }, set: { if !$0 { plannerError = nil } })) {
            Button("OK") { plannerError = nil }
        } message: { Text(plannerError ?? "Unknown planning error") }
        .onAppear {
            installUndoDeleteKeyboardMonitor()
            WindowManager.shared.applyWindowSettings()
            WindowManager.shared.applyActivationPolicy()
            seedCapacityOnly()
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
                    Text(selectedView.title).font(.system(size: 19, weight: .semibold))
                    Text("\(displayedTasks.count) pending").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                iconButton("minus", label: "Minimize") { WindowManager.shared.minimizeMainWindow() }
                iconButton("clock.arrow.circlepath", label: "Completed task history") { isCompletedHistoryPresented = true }
                iconButton("tag", label: "Manage categories") { isCategoriesPresented = true }
                Menu {
                    Button("New task", systemImage: "square.and.pencil") { isCreatingTask = true }
                    Button("Paste tasks", systemImage: "doc.on.clipboard") { isImportingTasks = true }
                } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("Add or import tasks").accessibilityLabel("Add or import tasks")
            }
            Picker("View", selection: $selectedView) {
                ForEach(PlannerMainView.allCases) { view in Text(view.title).tag(view) }
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack {
                CategoryFilterControl(categories: categories, storedFilter: $storedFilter)
                .frame(maxWidth: 210).accessibilityLabel("Filter tasks by category")
                Spacer()
                Button("Replan", systemImage: "arrow.triangle.2.circlepath") { replan() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    @ViewBuilder
    private var plannerContent: some View {
        switch selectedView {
        case .focus:
            FocusPlannerView(tasks: displayedTasks, blocks: workBlocks) { task in
                let oldValue = task.isCompleted
                task.setCompleted(true)
                handleCompletionChange(task: task, oldValue: oldValue, newValue: true)
            }
        case .tasks:
            VStack(spacing: 0) {
                Picker("Sort tasks", selection: $planSort) {
                    ForEach(TaskPlanSort.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.vertical, 9)
                taskList
            }
        case .week:
            WeekPlannerView(tasks: tasks, blocks: workBlocks, templates: capacityTemplates,
                            onMove: moveBlock, onToggleLock: toggleBlockLock) { task in
                let oldValue = task.isCompleted
                task.setCompleted(true)
                handleCompletionChange(task: task, oldValue: oldValue, newValue: true)
            }
        }
    }

    private var taskList: some View {
        List {
            if displayedTasks.isEmpty {
                ContentUnavailableView("No pending tasks", systemImage: "checkmark.circle", description: Text("Add a task to get started."))
                    .frame(maxWidth: .infinity).padding(.vertical, 42)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(displayedTasks) { task in
                TaskRow(task: task, showPlanMetadata: planSort == .plan, onUpdate: saveChanges, onCompletionChanged: handleCompletionChange) {
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
        replan(presentResult: false)
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

    private func seedCapacityOnly() {
        do {
            _ = try PlannerCoordinator.ensureDefaultCapacity(in: modelContext)
        } catch { plannerError = error.localizedDescription }
    }

    private func replan(presentResult: Bool = true) {
        do {
            appliedPlan = try PlannerCoordinator.replan(in: modelContext)
            if presentResult { isPlanUpdatePresented = true }
        } catch { plannerError = error.localizedDescription }
    }

    private func undoLastPlan() {
        guard let snapshot = appliedPlan?.undoSnapshot else { return }
        do { try PlannerCoordinator.undo(snapshot, in: modelContext); appliedPlan = nil }
        catch { plannerError = error.localizedDescription }
    }

    private func moveBlock(_ block: WorkBlock, to date: Date, lock: Bool) {
        block.date = Calendar.current.startOfDay(for: date)
        block.status = .moved
        if lock { block.locked = true }
        saveChanges()
    }

    private func toggleBlockLock(_ block: WorkBlock) {
        block.locked.toggle(); saveChanges()
    }
}

private struct DeletedTaskSnapshot {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let sortOrder: Int
    let createdAt: Date
    let scheduledDate: Date?
    let hasExplicitDueTime: Bool
    let completedAt: Date?
    let category: TaskCategory?
    let colorPriority: TaskColorPriority
    let planningPriorityRawValue: String?
    let prioritySourceRawValue: String?
    let repeatRule: TaskRepeatRule
    let recurrenceGroupID: String?
    let notes: String?
    let plannerValues: PlannerTaskValues

    init(task: TodoTask) {
        id = task.id; title = task.title; isCompleted = task.isCompleted; sortOrder = task.sortOrder; createdAt = task.createdAt
        scheduledDate = task.scheduledDate; hasExplicitDueTime = task.hasExplicitDueTime; completedAt = task.completedAt
        category = task.category; colorPriority = task.colorPriority
        planningPriorityRawValue = task.planningPriorityRawValue; prioritySourceRawValue = task.prioritySourceRawValue
        repeatRule = task.repeatRule; recurrenceGroupID = task.recurrenceGroupID
        notes = task.notes
        plannerValues = PlannerTaskValues(task: task)
    }

    func task() -> TodoTask {
        let restored = TodoTask(title: title, isCompleted: isCompleted, sortOrder: sortOrder, createdAt: createdAt,
                 scheduledDate: scheduledDate, hasExplicitDueTime: hasExplicitDueTime, completedAt: completedAt,
                 category: category, colorPriority: colorPriority, repeatRule: repeatRule, recurrenceGroupID: recurrenceGroupID)
        restored.id = id; restored.notes = notes
        restored.planningPriorityRawValue = planningPriorityRawValue
        restored.prioritySourceRawValue = prioritySourceRawValue
        plannerValues.apply(to: restored)
        return restored
    }
}

private struct PlannerTaskValues {
    let deadlineType: DeadlineType; let workMode: WorkMode; let size: TaskSize; let energy: EnergyDemand
    let estimatedMinutes: Int?; let estimatedBlocks: Int?; let splittable: Bool?; let minimumBlockMinutes: Int?
    let uncertainty: PlanningUncertainty; let startBy: Date?; let manualStartBy: Date?; let plannedStart: Date?; let executionRank: Int?
    let progress: Double?; let completedBlocks: Int?; let dependencies: [UUID]; let blockedBy: [UUID]
    let relatedMeetingDate: Date?; let plannerLocked: Bool?; let manualPriority: Int?; let plannerReason: String?; let aiConfidence: Double?
    init(task: TodoTask) {
        deadlineType = task.deadlineType; workMode = task.workMode; size = task.taskSize; energy = task.energyDemand
        estimatedMinutes = task.estimatedMinutes; estimatedBlocks = task.estimatedBlocks; splittable = task.splittable
        minimumBlockMinutes = task.minimumBlockMinutes; uncertainty = task.uncertainty; startBy = task.startBy
        manualStartBy = task.manualStartBy
        plannedStart = task.plannedStart; executionRank = task.executionRank; progress = task.progress
        completedBlocks = task.completedBlocks; dependencies = task.dependencyIDs; blockedBy = task.blockedBy
        relatedMeetingDate = task.relatedMeetingDate; plannerLocked = task.plannerLocked; manualPriority = task.manualPriority
        plannerReason = task.plannerReason; aiConfidence = task.aiConfidence
    }
    func apply(to task: TodoTask) {
        task.deadlineType = deadlineType; task.workMode = workMode; task.taskSize = size; task.energyDemand = energy
        task.estimatedMinutes = estimatedMinutes; task.estimatedBlocks = estimatedBlocks; task.splittable = splittable
        task.minimumBlockMinutes = minimumBlockMinutes; task.uncertainty = uncertainty; task.startBy = startBy
        task.manualStartBy = manualStartBy
        task.plannedStart = plannedStart; task.executionRank = executionRank; task.progress = progress
        task.completedBlocks = completedBlocks; task.dependencyIDs = dependencies; task.blockedBy = blockedBy
        task.relatedMeetingDate = relatedMeetingDate; task.plannerLocked = plannerLocked; task.manualPriority = manualPriority
        task.plannerReason = plannerReason; task.aiConfidence = aiConfidence
    }
}
