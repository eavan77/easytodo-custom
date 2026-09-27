import SwiftUI

enum DayTaskPresentation {
    static func tasks(on day: Date, from tasks: [TodoTask], blocks: [WorkBlock], calendar: Calendar = .current) -> [TodoTask] {
        let assignedIDs = Set(blocks.lazy.filter {
            calendar.isDate($0.date, inSameDayAs: day) && $0.status != .done && $0.status != .skipped
        }.map(\.taskID))
        return tasks.filter { !$0.isCompleted && assignedIDs.contains($0.id) }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }
}

struct FocusPlannerView: View {
    let tasks: [TodoTask]
    let blocks: [WorkBlock]
    var conflicts: [ScheduleConflict] = []
    var acknowledgedConflictKeys: Set<String> = []
    var onReviewConflicts: () -> Void = {}
    var onComplete: (TodoTask) -> Void

    private let calendar = Calendar.current

    private var todayTasks: [TodoTask] {
        DayTaskPresentation.tasks(on: .now, from: tasks, blocks: blocks, calendar: calendar)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if conflictSummary.hasAny { conflictBanner }
                sectionLabel("TODAY")
                if todayTasks.isEmpty {
                    ContentUnavailableView("Nothing planned", systemImage: "checkmark.circle",
                                           description: Text("Add a task or run Replan."))
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 7) {
                        ForEach(todayTasks) { task in taskRow(task) }
                    }
                }
            }
            .padding(16)
        }
    }

    private var conflictSummary: FocusConflictSummary {
        FocusConflictSummary(conflicts: conflicts, acknowledgedKeys: acknowledgedConflictKeys)
    }

    private var conflictBanner: some View {
        Button(action: onReviewConflicts) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    if conflictSummary.activeConflictCount > 0 {
                        Label(conflictSummary.activeText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if conflictSummary.acknowledgedConflictCount > 0 {
                        Label(conflictSummary.acknowledgedText, systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                    Text(conflictSummary.activeConflictCount > 0 ? "\(conflictSummary.riskDateText) · Review plan" : "Review later")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold)).padding(10)
            .background(.orange.opacity(conflictSummary.activeConflictCount > 0 ? 0.10 : 0.04),
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review schedule conflicts")
    }

    private func taskRow(_ task: TodoTask) -> some View {
        HStack(spacing: 9) {
            Button { onComplete(task) } label: {
                Image(systemName: "circle").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(task.title) complete")

            if let category = task.category {
                Circle().fill(category.color.swiftUIColor).frame(width: 7, height: 7).help(category.name)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.body.weight(.medium)).lineLimit(2)
                if let dueText = dueText(for: task) {
                    Text(dueText).font(.caption).foregroundStyle(dueColor(for: task))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(.secondary).tracking(0.8)
    }

    private func dueText(for task: TodoTask) -> String? {
        guard let due = task.scheduledDate else { return nil }
        if calendar.isDateInToday(due) { return "Due today" }
        if calendar.isDateInTomorrow(due) { return "Due tomorrow" }
        return nil
    }

    private func dueColor(for task: TodoTask) -> Color {
        guard let due = task.effectiveDeadline() else { return .secondary }
        return due < .now ? .orange : .secondary
    }
}

struct FocusConflictSummary: Equatable {
    let activeConflictCount: Int
    let acknowledgedConflictCount: Int
    let activeBlockCount: Int
    let acknowledgedBlockCount: Int
    let earliestActiveDate: Date?

    init(conflicts: [ScheduleConflict], acknowledgedKeys: Set<String>) {
        let unresolved = conflicts.filter { $0.required > $0.available }
        let active = unresolved.filter { !acknowledgedKeys.contains($0.conflictKey) }
        let acknowledged = unresolved.filter { acknowledgedKeys.contains($0.conflictKey) }
        activeConflictCount = active.count
        acknowledgedConflictCount = acknowledged.count
        activeBlockCount = active.reduce(0) { $0 + max(0, $1.required - $1.available) }
        acknowledgedBlockCount = acknowledged.reduce(0) { $0 + max(0, $1.required - $1.available) }
        earliestActiveDate = active.map(\.deadline).min()
    }

    var hasAny: Bool { activeConflictCount + acknowledgedConflictCount > 0 }
    var activeText: String {
        if activeConflictCount > 1 { return "\(activeConflictCount) schedule conflicts" }
        return "\(activeBlockCount) work block\(activeBlockCount == 1 ? " doesn't" : "s don't") fit"
    }
    var acknowledgedText: String {
        acknowledgedConflictCount == 1
            ? "\(acknowledgedBlockCount) unresolved work block\(acknowledgedBlockCount == 1 ? "" : "s")"
            : "\(acknowledgedConflictCount) unresolved items"
    }
    var riskDateText: String {
        guard let earliestActiveDate else { return "Unresolved" }
        return "Before \(earliestActiveDate.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
