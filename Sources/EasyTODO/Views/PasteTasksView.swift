import SwiftData
import SwiftUI

struct PasteTasksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingTasks: [TodoTask]
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]

    var onImported: ((AppliedPlan) -> Void)?

    @State private var rawText = ""
    @State private var parseResult: TaskTextParseResult?
    @State private var previewItems: [TaskImportPreviewItem] = []
    @State private var editingTask: ParsedTaskDTO?
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(parseResult == nil ? "Paste Tasks" : "Import Preview")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
            }

            if let successMessage {
                ContentUnavailableView("Import complete", systemImage: "checkmark.circle.fill",
                                       description: Text(successMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if parseResult == nil {
                Text("Paste one or more EasyTODO Task Format v1 or v2 tasks.")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $rawText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 420)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
                HStack {
                    Spacer()
                    Button("Parse") { parse() }
                        .buttonStyle(.borderedProminent)
                        .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("Ready to import: \(includedCount) task\(includedCount == 1 ? "" : "s")")
                    .font(.headline)
                if let result = parseResult {
                    ForEach(result.issues.filter { $0.taskIndex == nil }) { issue in
                        issueRow(issue)
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach($previewItems) { $item in
                            previewCard($item)
                        }
                    }
                }
                HStack {
                    Button("Back to text") {
                        parseResult = nil
                        previewItems = []
                    }
                    Spacer()
                    Button("Import \(includedCount) tasks") { commitImport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(includedCount == 0 || parseResult?.hasErrors == true)
                }
            }
        }
        .padding(18)
        .frame(width: 610, height: 650)
        .sheet(item: $editingTask) { dto in
            ImportTaskEditSheet(task: dto) { updated in
                guard let index = previewItems.firstIndex(where: { $0.id == updated.id }) else { return }
                var tasks = previewItems.map(\.dto)
                tasks[index] = updated
                let retainedIssues = parseResult?.issues.filter { $0.kind != .incompletePlannerMetadata } ?? []
                let refreshed = TaskTextParseResult(tasks: tasks, issues: retainedIssues)
                parseResult = refreshed
                previewItems = TaskImportCoordinator.preview(parseResult: refreshed,
                                                               existingTasks: existingTasks,
                                                               categories: categories)
            }
        }
        .alert("Unable to import", isPresented: Binding(get: { errorMessage != nil }, set: {
            if !$0 { errorMessage = nil }
        })) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "Unknown error") }
    }

    private var includedCount: Int { previewItems.filter { $0.isIncluded && !$0.hasErrors }.count }

    private func parse() {
        let result = EasyTodoTaskTextParser.parse(rawText)
        parseResult = result
        previewItems = TaskImportCoordinator.preview(parseResult: result, existingTasks: existingTasks,
                                                       categories: categories)
    }

    private func commitImport() {
        do {
            let result = try TaskImportCoordinator.importTasks(previewItems, in: modelContext)
            onImported?(result.plan)
            successMessage = "\(result.importedCount) task\(result.importedCount == 1 ? "" : "s") imported. Plan updated."
        } catch { errorMessage = error.localizedDescription }
    }

    private func previewCard(_ item: Binding<TaskImportPreviewItem>) -> some View {
        let value = item.wrappedValue
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Toggle(isOn: item.isIncluded) {
                    Text(value.dto.title.isEmpty ? "Untitled task" : value.dto.title).font(.headline)
                }
                .toggleStyle(.checkbox)
                Spacer()
                Button("Edit") { editingTask = value.dto }.buttonStyle(.plain)
            }
            Text(previewMetadata(value.dto)).font(.caption).foregroundStyle(.secondary)
            if let start = value.dto.manualStartBy {
                Text("Start by \(start.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption.weight(.medium))
            }
            if !value.dto.blocks.isEmpty {
                Text("BLOCKS").font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(Array(value.dto.blocks.enumerated()), id: \.element.id) { index, block in
                    Text("\(index + 1)  \(block.name) · \(block.estimatedMinutes.map { "\($0) min" } ?? "Auto") · \(block.splittable ? "Splittable" : "One session")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let project = value.dto.projectName {
                Text(project).font(.caption.weight(.medium))
            }
            if value.issues.contains(where: { $0.kind == .unknownProject }) {
                Picker("Project", selection: item.projectChoice) {
                    Text("No project").tag(ImportProjectChoice.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(ImportProjectChoice.existing(category.id))
                    }
                    if let project = value.dto.projectName {
                        Text("Create “\(project)”").tag(ImportProjectChoice.create(project))
                    }
                }
            }
            ForEach(value.issues) { issue in issueRow(issue) }
            if value.isPossibleDuplicate && !value.isIncluded {
                Button("Import anyway") { item.isIncluded.wrappedValue = true }
                    .controlSize(.small)
            }
        }
        .padding(11)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func issueRow(_ issue: ImportValidationIssue) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(issue.severity.rawValue).font(.caption2.bold())
                .foregroundStyle(issue.severity == .error ? .red : .orange)
            Text((issue.line.map { "Line \($0): " } ?? "") + issue.message)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func previewMetadata(_ task: ParsedTaskDTO) -> String {
        let due = task.dueDate?.formatted(date: .abbreviated,
                                          time: task.hasExplicitDueTime ? .shortened : .omitted) ?? "No due date"
        let deadline: String
        switch task.deadlineType {
        case .some(.hard): deadline = "Official"
        case .some(.internalDeadline): deadline = "My deadline"
        case .some(.none): deadline = "No deadline"
        case .some(.soft): deadline = "Soft"
        case nil: deadline = "Needs confirmation"
        }
        let priority: String
        if let explicit = task.priority { priority = explicit.title }
        else if FixedAssessmentRecognizer.match(in: task.title) != nil { priority = "Critical · Auto" }
        else { priority = "Normal · Auto" }
        let planning = [priority, task.size?.rawValue, task.workMode?.title,
                        (task.blocks.isEmpty ? task.estimatedBlocks : task.blocks.count).map { "\($0) blocks" }]
            .compactMap { $0 }.joined(separator: " · ")
        return [due, deadline, planning].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ImportTaskEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var task: ParsedTaskDTO
    let onSave: (ParsedTaskDTO) -> Void

    init(task: ParsedTaskDTO, onSave: @escaping (ParsedTaskDTO) -> Void) {
        _task = State(initialValue: task)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            TextField("Title", text: $task.title)
            TextField("Project", text: Binding(get: { task.projectName ?? "" }, set: {
                task.projectName = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
            }))
            Picker("Deadline", selection: $task.deadlineType) {
                Text("Needs confirmation").tag(Optional<DeadlineType>.none)
                Text("Official").tag(Optional(DeadlineType.hard))
                Text("My deadline").tag(Optional(DeadlineType.internalDeadline))
                Text("None").tag(Optional(DeadlineType.none))
            }
            Picker("Priority", selection: $task.priority) {
                Text("Auto").tag(Optional<TaskPriority>.none)
                ForEach(TaskPriority.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Toggle("Manual Start By", isOn: Binding(get: { task.manualStartBy != nil }, set: {
                task.manualStartBy = $0 ? (task.manualStartBy ?? task.dueDate ?? .now) : nil
            }))
            if task.manualStartBy != nil {
                DatePicker("Start by", selection: Binding(get: { task.manualStartBy ?? .now },
                                                          set: { task.manualStartBy = $0 }), displayedComponents: .date)
            }
            Picker("Work type", selection: $task.workMode) {
                Text("Unspecified").tag(Optional<WorkMode>.none)
                ForEach(WorkMode.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Picker("Size", selection: $task.size) {
                Text("Unspecified").tag(Optional<TaskSize>.none)
                ForEach(TaskSize.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            Section("Blocks") {
                ForEach($task.blocks) { $block in
                    VStack(alignment: .leading) {
                        TextField("Block name", text: $block.name)
                        TextField("Minutes (blank = Auto)", text: optionalInteger($block.estimatedMinutes))
                        Toggle("Splittable", isOn: $block.splittable)
                        TextField("Minimum session (blank = Auto)", text: optionalInteger($block.minimumSessionMinutes))
                    }
                }
                Button("Add block") { task.blocks.append(ParsedBlockDTO(name: "Block \(task.blocks.count + 1)")) }
            }
            Picker("Energy", selection: $task.energy) {
                Text("Unspecified").tag(Optional<EnergyDemand>.none)
                ForEach(EnergyDemand.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Picker("Uncertainty", selection: $task.uncertainty) {
                Text("Unspecified").tag(Optional<PlanningUncertainty>.none)
                ForEach(PlanningUncertainty.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Toggle("Can split", isOn: Binding(get: { task.splittable ?? true }, set: { task.splittable = $0 }))
            TextField("Notes", text: $task.notes)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    if task.deadlineType != nil {
                        task.deadlineTypeSource = .userSelected
                    } else {
                        task.deadlineTypeSource = nil
                    }
                    task.prioritySource = task.priority == nil ? nil : .userSelected
                    onSave(task); dismiss()
                }
                .disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 500)
    }

    private func optionalInteger(_ value: Binding<Int?>) -> Binding<String> {
        Binding(get: { value.wrappedValue.map(String.init) ?? "" }, set: {
            value.wrappedValue = Int($0).flatMap { $0 > 0 ? $0 : nil }
        })
    }
}
