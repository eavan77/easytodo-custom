import SwiftData
import SwiftUI

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    @Query private var allTasks: [TodoTask]
    @Query private var allBlocks: [WorkBlock]
    @Query private var allBlockDefinitions: [TaskBlockDefinition]
    @Bindable var task: TodoTask

    @State private var hasDueDate = false
    @State private var hasDueTime = false
    @State private var dueDate = Date()
    @State private var selectedDeadlineType: DeadlineType?
    @State private var deadlineTypeWasChanged = false
    @State private var selectedPriority: TaskPriority = .normal
    @State private var priorityWasChanged = false
    @State private var isEstimatingTask = false
    @State private var manualStartByEnabled = false
    @State private var manualStartByDate = Date()
    @State private var editingBlock: TaskBlockDefinition?

    var body: some View {
        Form {
            Section {
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
                    VStack(alignment: .leading, spacing: 5) {
                        Picker("Deadline type", selection: explicitDeadlineBinding) {
                            Text("Official").tag(Optional(DeadlineType.hard))
                            Text("My deadline").tag(Optional(DeadlineType.internalDeadline))
                        }
                        .pickerStyle(.segmented)
                        if selectedDeadlineType == nil {
                            Label("Needs confirmation", systemImage: "questionmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Toggle("Completed", isOn: completionBinding)
            }

            Section("Planning") {
                VStack(alignment: .leading, spacing: 5) {
                    Picker("Priority", selection: priorityBinding) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(priorityWasChanged ? "User selected" : task.prioritySourceDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if task.needsPlannerMetadata {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Estimate needed", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                        Text("Planning defaults are temporary until you confirm this task.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Estimate task") { isEstimatingTask = true }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        LabeledContent("Start by") {
                            Text(task.effectiveStartBy?.formatted(date: .abbreviated, time: .omitted) ?? "After Replan")
                            Text(task.manualStartBy == nil ? "Planner" : "Manual")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Edit") {
                            manualStartByEnabled = true
                            manualStartByDate = task.effectiveStartBy ?? .now
                        }.controlSize(.small)
                    }
                    if manualStartByEnabled {
                        DatePicker("Manual Start By", selection: $manualStartByDate, displayedComponents: .date)
                        HStack {
                            Button("Apply") { task.manualStartBy = Calendar.current.startOfDay(for: manualStartByDate); manualStartByEnabled = false }
                            if task.manualStartBy != nil {
                                Button("Use planner recommendation") { task.manualStartBy = nil; manualStartByEnabled = false }
                            }
                        }.controlSize(.small)
                    }
                }
                LabeledContent("Deadline type") {
                    Text(deadlineTypeLabel).foregroundStyle(selectedDeadlineType == nil ? .secondary : .primary)
                }
                LabeledContent("Deadline source") {
                    Text(deadlineSourceLabel).foregroundStyle(.secondary)
                }
                if !task.needsPlannerMetadata {
                    LabeledContent("Size", value: task.taskSize.rawValue)
                    LabeledContent("Work type", value: task.workMode.title)
                    LabeledContent("Estimated", value: "\(task.safeEstimatedBlocks) block\(task.safeEstimatedBlocks == 1 ? "" : "s")")
                    LabeledContent("Energy", value: task.energyDemand.title)
                    LabeledContent("Uncertainty", value: task.uncertainty.title)
                    LabeledContent("Can split", value: (task.splittable ?? true) ? "Yes" : "No")
                    Button("Edit estimate") { isEstimatingTask = true }
                }
                LabeledContent("Progress") { Text("\(task.safeCompletedBlocks) / \(task.safeEstimatedBlocks) blocks") }
            }

            Section("Blocks") {
                ForEach(taskDefinitions) { definition in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(definition.orderIndex + 1). \(definition.title)")
                            Text(blockSummary(definition)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { move(definition, offset: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain).disabled(definition.orderIndex == 0)
                        Button { move(definition, offset: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain).disabled(definition.orderIndex >= taskDefinitions.count - 1)
                        Button("Edit") { editingBlock = definition }.controlSize(.small)
                    }
                }
                Button("Add block") {
                    let definition = TaskBlockDefinition(taskID: task.id, orderIndex: taskDefinitions.count,
                                                         title: "Block \(taskDefinitions.count + 1)",
                                                         splittable: task.splittable ?? true,
                                                         minimumSessionMinutes: task.minimumBlockMinutes)
                    modelContext.insert(definition); task.estimatedBlocks = taskDefinitions.count + 1
                    editingBlock = definition
                }
            }

            Section("Notes") {
                TextField("Notes", text: Binding(get: { task.notes ?? "" }, set: { task.notes = $0.isEmpty ? nil : $0 }))
            }

            Section("Why this plan") {
                Text(task.plannerReason ?? "Run Replan to calculate a capacity-aware plan.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Dependencies") {
                if dependencyCandidates.isEmpty { Text("No other active tasks").foregroundStyle(.secondary) }
                ForEach(dependencyCandidates) { candidate in
                    Toggle(candidate.title, isOn: dependencyBinding(candidate.id))
                }
                let followers = allTasks.filter { $0.dependencyIDs.contains(task.id) && !$0.isCompleted }
                if !followers.isEmpty {
                    LabeledContent("Followed by") { Text(followers.map(\.title).joined(separator: ", ")) }
                }
            }

            Section("Sessions") {
                if taskBlocks.isEmpty { Text("No sessions yet").foregroundStyle(.secondary) }
                ForEach(taskBlocks) { block in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(block.date.formatted(.dateTime.weekday(.abbreviated))) · \(block.period.title)")
                            Text("\(definitionTitle(for: block)) · Session \(sessionNumber(block)) · \(block.estimatedMinutes) min")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { block.locked.toggle() } label: { Image(systemName: block.locked ? "lock.fill" : "lock.open") }
                            .buttonStyle(.plain).help(block.locked ? "Unlock block" : "Keep here")
                    }
                }
                Button("Replan this task", systemImage: "arrow.triangle.2.circlepath") {
                    save(postPlanningChange: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save(postPlanningChange: true) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 650)
        .onAppear {
            hasDueDate = task.scheduledDate != nil
            hasDueTime = task.hasExplicitDueTime
            dueDate = task.scheduledDate ?? .now
            selectedDeadlineType = task.explicitDeadlineType
            selectedPriority = task.priority
            manualStartByDate = task.effectiveStartBy ?? .now
        }
        .onChange(of: hasDueDate) { _, enabled in
            if enabled, selectedDeadlineType == DeadlineType.none { selectedDeadlineType = nil }
        }
        .sheet(isPresented: $isEstimatingTask) {
            TaskEstimateSheet(task: task) {
                try? modelContext.save()
                NotificationCenter.default.post(name: .easyTODOPlanningInputsChanged, object: task.id)
            }
        }
        .sheet(item: $editingBlock) { definition in
            TaskBlockDefinitionEditor(definition: definition, canDelete: taskDefinitions.count > 1,
                                      onDuplicate: { duplicate(definition) }, onDelete: { delete(definition) }) {
                task.estimatedBlocks = taskDefinitions.count
                try? modelContext.save()
                NotificationCenter.default.post(name: .easyTODOPlanningInputsChanged, object: task.id)
            }
        }
    }

    private var dependencyCandidates: [TodoTask] {
        allTasks.filter { $0.id != task.id && !$0.isCompleted }.sorted { $0.title < $1.title }
    }

    private var taskBlocks: [WorkBlock] {
        allBlocks.filter { $0.taskID == task.id }.sorted { $0.date < $1.date }
    }
    private var taskDefinitions: [TaskBlockDefinition] {
        allBlockDefinitions.filter { $0.taskID == task.id }.sorted { $0.orderIndex < $1.orderIndex }
    }
    private func blockSummary(_ definition: TaskBlockDefinition) -> String {
        let sessions = taskBlocks.filter { $0.taskBlockDefinitionID == definition.id && $0.status != .skipped }
        let done = sessions.filter { $0.status == .done }.count
        let duration = definition.estimatedMinutes.map { "\($0) min" } ?? "Auto"
        let shape = definition.splittable ? "Splittable" : "One session"
        let progress = sessions.isEmpty ? "Not scheduled" : "\(done) / \(sessions.count) sessions complete"
        return "\(duration) · \(shape) · \(progress)"
    }
    private func definitionTitle(for session: WorkBlock) -> String {
        taskDefinitions.first { $0.id == session.taskBlockDefinitionID }?.title ?? "Legacy block"
    }
    private func sessionNumber(_ session: WorkBlock) -> Int { (session.sessionOrderIndex ?? 0) + 1 }
    private func move(_ definition: TaskBlockDefinition, offset: Int) {
        let target = definition.orderIndex + offset
        guard let other = taskDefinitions.first(where: { $0.orderIndex == target }) else { return }
        other.orderIndex = definition.orderIndex; definition.orderIndex = target
    }
    private func duplicate(_ definition: TaskBlockDefinition) {
        taskDefinitions.filter { $0.orderIndex > definition.orderIndex }.forEach { $0.orderIndex += 1 }
        modelContext.insert(TaskBlockDefinition(taskID: task.id, orderIndex: definition.orderIndex + 1,
                                                title: definition.title + " Copy",
                                                estimatedMinutes: definition.estimatedMinutes,
                                                splittable: definition.splittable,
                                                minimumSessionMinutes: definition.minimumSessionMinutes))
    }
    private func delete(_ definition: TaskBlockDefinition) {
        taskBlocks.filter { $0.taskBlockDefinitionID == definition.id }.forEach { $0.taskBlockDefinitionID = nil }
        modelContext.delete(definition)
        taskDefinitions.filter { $0.orderIndex > definition.orderIndex }.forEach { $0.orderIndex -= 1 }
    }

    private var explicitDeadlineBinding: Binding<DeadlineType?> {
        Binding(get: { selectedDeadlineType }, set: {
            selectedDeadlineType = $0
            deadlineTypeWasChanged = true
        })
    }
    private var priorityBinding: Binding<TaskPriority> {
        Binding(get: { selectedPriority }, set: {
            selectedPriority = $0
            priorityWasChanged = true
        })
    }
    private var deadlineTypeLabel: String {
        guard hasDueDate else { return "None" }
        switch selectedDeadlineType {
        case .some(.hard): return "Official deadline"
        case .some(.internalDeadline): return "My deadline"
        case .some(.soft): return "Flexible deadline"
        case .some(.none): return "None"
        case nil: return "Needs confirmation"
        }
    }
    private var deadlineSourceLabel: String {
        deadlineTypeWasChanged ? "User selected" : task.deadlineSourceDescription
    }
    private func dependencyBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { task.dependencyIDs.contains(id) }, set: { selected in
            var ids = task.dependencyIDs
            if selected { if !ids.contains(id) { ids.append(id) } } else { ids.removeAll { $0 == id } }
            task.dependencyIDs = ids
        })
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

    private func save(postPlanningChange: Bool = false) {
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.setDueDate(hasDueDate ? dueDate : nil, includesTime: hasDueDate && hasDueTime)
        if priorityWasChanged {
            task.userSelectPriority(selectedPriority)
        } else if task.prioritySource != .userSelected {
            if FixedAssessmentRecognizer.match(in: task.title) != nil {
                task.priority = .critical
                task.prioritySource = .autoDetected
            } else {
                task.priority = .normal
                task.prioritySource = .default
            }
        }
        if !hasDueDate { task.setDeadlineType(.none, source: .userSelected) }
        else if let selectedDeadlineType, selectedDeadlineType != .none, deadlineTypeWasChanged {
            task.userSelectDeadlineType(selectedDeadlineType)
        }
        else if let selectedDeadlineType, selectedDeadlineType != .none, task.deadlineTypeRawValue != nil {
            task.deadlineType = selectedDeadlineType
        }
        else if let match = FixedAssessmentRecognizer.match(in: task.title) {
            task.setDeadlineType(.hard, source: .autoDetected)
            task.plannerReason = "Fixed assessment detected from “\(match.phrase)”."
        }
        else { task.deadlineTypeRawValue = nil }
        try? modelContext.save()
        if postPlanningChange { NotificationCenter.default.post(name: .easyTODOPlanningInputsChanged, object: task.id) }
        dismiss()
    }
}
