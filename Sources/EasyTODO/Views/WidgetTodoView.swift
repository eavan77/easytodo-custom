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
    @Query private var workBlocks: [WorkBlock]
    @Query(sort: \DayCapacityTemplate.weekday) private var capacityTemplates: [DayCapacityTemplate]
    @Query private var conflictAcknowledgements: [ScheduleConflictAcknowledgement]
    @AppStorage(EasyTODOSettings.theme) private var theme = ThemeOption.light.rawValue
    @AppStorage(EasyTODOSettings.widgetCategoryFilter) private var storedFilter = "all"
    @State private var newTaskTitle = ""
    @State private var editingTask: TodoTask?
    @State private var isCreatingTask = false
    @State private var isImportingTasks = false
    @State private var isManagingCategories = false
    @State private var selectedView: PlannerMainView = .focus
    @State private var planSort: TaskPlanSort = .plan
    @State private var appliedPlan: AppliedPlan?
    @State private var isPlanUpdatePresented = false
    @State private var plannerError: String?
    @FocusState private var quickAddFocused: Bool

    private var filter: TaskCategoryFilter { TaskCategoryFilter(storedValue: storedFilter) }
    private var visibleTasks: [TodoTask] {
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
        VStack(alignment: .leading, spacing: 10) {
            header
            viewPicker
            quickAdd
            plannerContent
            footer
        }
        .padding(13).frame(width: 420, height: 560, alignment: .top)
        .foregroundStyle(.primary)
        .modifier(WidgetGlassSurface(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(count: 2) { WindowManager.shared.showMainWindow() }
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task)
                .onAppear { WidgetWindowManager.shared.beginChildInteraction(.taskEditor) }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction(.taskEditor) }
        }
        .sheet(isPresented: $isCreatingTask) {
            TaskCreationView(initialCategoryID: selectedCategoryID)
                .onAppear { WidgetWindowManager.shared.beginChildInteraction(.taskCreation) }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction(.taskCreation) }
        }
        .sheet(isPresented: $isImportingTasks) {
            PasteTasksView { plan in self.appliedPlan = plan }
                .onAppear { WidgetWindowManager.shared.beginChildInteraction(.taskImport) }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction(.taskImport) }
        }
        .sheet(isPresented: $isManagingCategories) {
            CategoryManagementView()
                .onAppear { WidgetWindowManager.shared.beginChildInteraction(.categoryManagement) }
                .onDisappear { WidgetWindowManager.shared.endChildInteraction(.categoryManagement) }
        }
        .sheet(isPresented: $isPlanUpdatePresented) {
            if let appliedPlan {
                PlanUpdateView(plan: appliedPlan, onUndo: undoLastPlan) { updated in
                    self.appliedPlan = updated
                }
                    .onAppear { WidgetWindowManager.shared.beginChildInteraction(.planUpdate) }
                    .onDisappear { WidgetWindowManager.shared.endChildInteraction(.planUpdate) }
            }
        }
        .alert("Unable to Replan", isPresented: Binding(get: { plannerError != nil }, set: { if !$0 { plannerError = nil } })) {
            Button("OK") { plannerError = nil }
        } message: { Text(plannerError ?? "Unknown planning error") }
        .onChange(of: quickAddFocused) { _, focused in
            focused
                ? WidgetWindowManager.shared.beginChildInteraction(.quickAdd)
                : WidgetWindowManager.shared.endChildInteraction(.quickAdd)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // A nonactivating panel does not reliably clear SwiftUI focus when the
            // user clicks another app. Releasing it here also releases the one
            // interaction lock owned by the quick-add editor.
            quickAddFocused = false
        }
        .onChange(of: categories.map(\.id)) { _, categoryIDs in
            if case let .category(id) = filter, !categoryIDs.contains(id) {
                storedFilter = "all"
            }
        }
        .onAppear { seedPlannerIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .easyTODOPlanningInputsChanged)) { _ in
            replan(presentResult: false)
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(selectedView.title, systemImage: "checklist").font(.system(size: 14, weight: .semibold))
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

    private var viewPicker: some View {
        Picker("Planner view", selection: $selectedView) {
            ForEach(PlannerMainView.allCases) { view in Text(view.title).tag(view) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var plannerContent: some View {
        switch selectedView {
        case .focus:
            FocusPlannerView(tasks: visibleTasks, blocks: workBlocks,
                             conflicts: appliedPlan?.output.conflicts ?? [],
                             acknowledgedConflictKeys: Set(conflictAcknowledgements.map(\.conflictKey)),
                             onReviewConflicts: reviewConflicts,
                             onComplete: complete)
        case .tasks:
            VStack(spacing: 7) {
                Picker("Sort tasks", selection: $planSort) {
                    ForEach(TaskPlanSort.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if visibleTasks.isEmpty { emptyState } else { taskList }
            }
        case .week:
            WeekPlannerView(tasks: tasks, blocks: workBlocks, templates: capacityTemplates,
                            conflictedTaskIDs: conflictedTaskIDs,
                            onMove: moveBlock, onToggleLock: toggleBlockLock,
                            onComplete: complete)
        }
    }

    private var quickAdd: some View {
        AddTaskBar(title: $newTaskTitle, isFocused: $quickAddFocused) {
            addTask()
            quickAddFocused = false
        } onNewTask: {
            isCreatingTask = true
        } onPasteTasks: {
            isImportingTasks = true
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(visibleTasks) { task in
                    taskRow(task).transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .frame(maxHeight: .infinity).scrollIndicators(.visible)
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
                if let metadata = taskMetadata(task) {
                    Text(metadata).font(.system(size: 10, weight: .medium))
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
        HStack {
            Button("Replan", systemImage: "arrow.triangle.2.circlepath") { replan() }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Spacer()
            Button { WindowManager.shared.showMainWindow() } label: {
                Image(systemName: "arrow.up.right.square")
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Open main window")
        }
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
    private func taskMetadata(_ task: TodoTask) -> String? {
        guard planSort == .plan else { return DeadlineFormatting.text(for: task) }
        let start = task.plannedStart.map { "Start \(shortDate($0))" }
        let due = task.scheduledDate.map { "Due \(shortDate($0))" }
        let dates = [start, due].compactMap { $0 }.joined(separator: " · ")
        let priority = task.priority == .normal ? nil : task.priority.title
        let planningDetail = task.needsPlannerMetadata ? "Estimate needed" :
            [priority, task.taskSize.rawValue, task.workMode.title].compactMap { $0 }.joined(separator: " · ")
        return [[dates.isEmpty ? nil : dates].compactMap { $0 }.joined(separator: "  "),
                planningDetail].joined(separator: "  ")
    }
    private func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    private func seedPlannerIfNeeded() {
        do {
            _ = try PlannerCoordinator.ensureDefaultCapacity(in: modelContext)
            let today = Calendar.current.startOfDay(for: .now)
            let missed = workBlocks.filter { !$0.locked && $0.status == .planned && $0.date < today }
            missed.forEach { $0.status = .skipped }
            replan(presentResult: false)
        } catch { plannerError = error.localizedDescription }
    }
    private func replan(presentResult: Bool = true) {
        do {
            appliedPlan = try PlannerCoordinator.replan(in: modelContext)
            if presentResult { isPlanUpdatePresented = true }
        } catch { plannerError = error.localizedDescription }
    }
    private func reviewConflicts() {
        if appliedPlan?.output.conflicts.isEmpty == false {
            isPlanUpdatePresented = true
        } else {
            replan(presentResult: false)
            if appliedPlan?.output.conflicts.isEmpty == false { isPlanUpdatePresented = true }
        }
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
    private func toggleBlockLock(_ block: WorkBlock) { block.locked.toggle(); saveChanges() }
    private func saveChanges() {
        do { try modelContext.save() }
        catch { plannerError = error.localizedDescription }
    }
    private var selectedCategoryID: UUID? {
        if case let .category(id) = filter { return id }
        return nil
    }
    private var preferredColorScheme: ColorScheme? { (ThemeOption(rawValue: theme) ?? .light) == .light ? .light : .dark }

    private var conflictedTaskIDs: Set<UUID> {
        Set(appliedPlan?.output.conflicts.flatMap(\.taskIDs) ?? [])
    }

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
