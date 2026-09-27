import SwiftData
import SwiftUI

struct PlanUpdateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]
    @Query private var blocks: [WorkBlock]
    @Query private var templates: [DayCapacityTemplate]
    @Query private var overrides: [DayCapacityOverride]
    @Query private var definitions: [TaskBlockDefinition]

    let plan: AppliedPlan
    var onUndo: () -> Void
    var onApplied: (AppliedPlan) -> Void

    @State private var conflictIndex = 0
    @State private var showMore = false
    @State private var selectedCandidate: ConflictResolutionCandidate?
    @State private var editingOfficialTask: TodoTask?
    @State private var estimateValues: [UUID: Int] = [:]
    @State private var errorMessage: String?

    private var conflicts: [ScheduleConflict] { plan.output.conflicts.sorted { $0.deadline < $1.deadline } }
    private var currentConflict: ScheduleConflict? { conflicts.indices.contains(conflictIndex) ? conflicts[conflictIndex] : nil }
    private var ranked: RankedConflictCandidates {
        guard let currentConflict else { return RankedConflictCandidates(all: []) }
        return ConflictResolver.candidates(for: currentConflict, tasks: tasks, templates: templates,
                                           overrides: overrides, blocks: blocks, currentOutput: plan.output,
                                           definitions: definitions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(conflicts.isEmpty ? "PLAN UPDATED" : "SCHEDULE CONFLICT").font(.title3.weight(.bold))
                if let conflict = currentConflict { conflictContent(conflict) } else { updatedContent }
                HStack {
                    Spacer()
                    if conflicts.isEmpty { Button("Undo") { onUndo(); dismiss() } }
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }.padding(20)
        }
        .frame(width: 500, height: conflicts.isEmpty ? 260 : 600)
        .confirmationDialog("Apply this change?", isPresented: Binding(
            get: { selectedCandidate != nil }, set: { if !$0 { selectedCandidate = nil } }
        ), titleVisibility: .visible) {
            Button(confirmLabel) { applySelectedCandidate() }
            Button("Cancel", role: .cancel) { selectedCandidate = nil }
        } message: { Text(selectedCandidate?.summary ?? "") }
        .sheet(item: $editingOfficialTask) { task in TaskEditorView(task: task) }
        .alert("Unable to update plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unknown error") }
    }

    private var updatedContent: some View {
        ForEach(plan.summary.isEmpty ? ["The current plan fits safe capacity."] : plan.summary, id: \.self) {
            Text($0).font(.callout)
        }
    }

    private func conflictContent(_ conflict: ScheduleConflict) -> some View {
        let missing = max(0, conflict.required - conflict.available)
        let affected = tasks.filter { conflict.taskIDs.contains($0.id) }.sorted { $0.title < $1.title }
        return VStack(alignment: .leading, spacing: 14) {
            if conflicts.count > 1 {
                HStack {
                    Text("Conflict \(conflictIndex + 1) of \(conflicts.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Previous") { conflictIndex = max(0, conflictIndex - 1); showMore = false }.disabled(conflictIndex == 0)
                    Button("Next") { conflictIndex = min(conflicts.count - 1, conflictIndex + 1); showMore = false }
                        .disabled(conflictIndex == conflicts.count - 1)
                }.controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(missing) \(conflict.mode.title) block\(missing == 1 ? " doesn't" : "s don't") fit before \(conflict.deadline.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.headline)
                ForEach(affected) { task in
                    Text("\(task.title) · \(deadlineLabel(task)) · \(task.remainingBlocks) blocks")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Text("RECOMMENDED").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(ranked.topCandidates) { candidate in candidateCard(candidate) }

            if !ranked.remainingCandidates.isEmpty {
                DisclosureGroup("More options", isExpanded: $showMore) {
                    VStack(spacing: 9) {
                        ForEach(ranked.remainingCandidates) { candidate in candidateCard(candidate) }
                    }.padding(.top, 8)
                }.font(.callout.weight(.medium))
            }
        }
    }

    private func candidateCard(_ candidate: ConflictResolutionCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(candidate.title).font(.headline)
                Spacer()
                if candidate.resolvesConflict {
                    Label("Resolves", systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                }
            }
            Text(candidate.summary).font(.callout)
            Text(candidate.outcome).font(.caption.weight(.medium))
            if let tradeoff = candidate.tradeoff { Text(tradeoff).font(.caption).foregroundStyle(.secondary) }

            if !candidate.previewChanges.isEmpty {
                DisclosureGroup("View changes") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(candidate.previewChanges) { Text($0.summary).font(.caption) }
                    }.padding(.top, 4)
                }.font(.caption.weight(.medium))
            }

            if case let .adjustEstimatedWork(taskID, _, _) = candidate.action,
               let task = tasks.first(where: { $0.id == taskID }) {
                Stepper("Estimated blocks: \(estimateValues[taskID] ?? task.safeEstimatedBlocks)",
                        value: estimateBinding(for: task), in: max(1, task.safeCompletedBlocks)...12)
                    .font(.caption)
                Button("Preview estimate") { previewEstimate(task: task, candidate: candidate) }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                if candidate.type == .keepUnresolved {
                    Button(actionLabel(candidate)) { handle(candidate) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Button(actionLabel(candidate)) { handle(candidate) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .padding(11)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

    private func handle(_ candidate: ConflictResolutionCandidate) {
        if case let .officialDeadlineAdjustment(taskID) = candidate.action {
            editingOfficialTask = tasks.first { $0.id == taskID }
        } else if candidate.requiresConfirmation {
            selectedCandidate = candidate
        } else {
            apply(candidate)
        }
    }

    private func previewEstimate(task: TodoTask, candidate: ConflictResolutionCandidate) {
        guard let conflict = currentConflict else { return }
        let count = estimateValues[task.id] ?? task.safeEstimatedBlocks
        guard let adjusted = ConflictResolver.adjustedEstimateCandidate(task: task, to: count,
                                                                         conflict: conflict, tasks: tasks,
                                                                         templates: templates, overrides: overrides,
                                                                         blocks: blocks, currentOutput: plan.output,
                                                                         definitions: definitions) else {
            errorMessage = "That estimate does not improve this conflict."
            return
        }
        selectedCandidate = adjusted
    }

    private func estimateBinding(for task: TodoTask) -> Binding<Int> {
        Binding(get: { estimateValues[task.id] ?? task.safeEstimatedBlocks },
                set: { estimateValues[task.id] = $0 })
    }

    private func applySelectedCandidate() {
        guard let selectedCandidate else { return }
        self.selectedCandidate = nil
        apply(selectedCandidate)
    }

    private func apply(_ candidate: ConflictResolutionCandidate) {
        do {
            let updated = try PlannerCoordinator.apply(candidate, in: modelContext)
            onApplied(updated)
            if candidate.type == .keepUnresolved { dismiss() }
        } catch { errorMessage = error.localizedDescription }
    }

    private var confirmLabel: String {
        switch selectedCandidate?.type {
        case .dayCapacityOverride: "Allow once"
        case .emergencyOverride: "Override once"
        default: "Apply"
        }
    }

    private func actionLabel(_ candidate: ConflictResolutionCandidate) -> String {
        switch candidate.type {
        case .dayCapacityOverride: "Allow once"
        case .emergencyOverride: "Override once"
        case .officialDeadlineAdjustment: "Review task"
        case .keepUnresolved: "Review later"
        default: "Apply"
        }
    }

    private func deadlineLabel(_ task: TodoTask) -> String {
        switch task.deadlineType {
        case .hard: task.deadlineTypeSource == .autoDetected ? "Official · Auto-detected" : "Official"
        case .internalDeadline: "My deadline"
        case .soft: "Flexible"
        case .none: "No deadline"
        }
    }
}
