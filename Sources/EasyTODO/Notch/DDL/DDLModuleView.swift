import SwiftData
import SwiftUI

struct DDLModuleView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TodoTask]
    @Query private var blocks: [WorkBlock]
    @Query private var conflictAcknowledgements: [ScheduleConflictAcknowledgement]

    @State private var editingTask: TodoTask?
    @State private var isCreatingTask = false
    @State private var appliedPlan: AppliedPlan?
    @State private var isPlanUpdatePresented = false
    @State private var plannerError: String?

    private let calendar = Calendar.current

    private var pendingCount: Int {
        tasks.filter { !$0.isCompleted }.count
    }

    private var todayTasks: [TodoTask] {
        DayTaskPresentation.tasks(
            on: .now,
            from: tasks,
            blocks: blocks,
            calendar: calendar
        )
    }

    private var tomorrowTasks: [TodoTask] {
        guard let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: .now
        ) else {
            return []
        }

        return DayTaskPresentation.tasks(
            on: tomorrow,
            from: tasks,
            blocks: blocks,
            calendar: calendar
        )
    }

    private var conflictSummary: FocusConflictSummary {
        FocusConflictSummary(
            conflicts: appliedPlan?.output.conflicts ?? [],
            acknowledgedKeys: Set(conflictAcknowledgements.map(\.conflictKey))
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    taskSection(
                        title: "TODAY",
                        tasks: todayTasks,
                        emptyText: "Nothing planned today"
                    )

                    Divider()
                        .overlay(Color.white.opacity(0.10))
                        .padding(.horizontal, 14)

                    taskSection(
                        title: "TOMORROW",
                        tasks: tomorrowTasks,
                        emptyText: "Nothing planned tomorrow"
                    )
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            Button {
                WindowManager.shared.showMainWindow()
            } label: {
                HStack(spacing: 5) {
                    Spacer()

                    Text("All Tasks")

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingTask) { task in
            TaskEditorView(task: task)
                .frame(minWidth: 420, minHeight: 520)
        }
        .sheet(isPresented: $isCreatingTask) {
            TaskCreationView()
        }
        .sheet(isPresented: $isPlanUpdatePresented) {
            if let appliedPlan {
                PlanUpdateView(
                    plan: appliedPlan,
                    onUndo: undoLastPlan
                ) { updated in
                    self.appliedPlan = updated
                }
            }
        }
        .alert(
            "Unable to Replan",
            isPresented: Binding(
                get: { plannerError != nil },
                set: { if !$0 { plannerError = nil } }
            )
        ) {
            Button("OK") {
                plannerError = nil
            }
        } message: {
            Text(plannerError ?? "Unknown planning error")
        }
        .onAppear {
            refreshPlanState()
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(pendingCount) pending")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.50))

            Spacer()

            if conflictSummary.activeConflictCount > 0 {
                Button {
                    reviewConflicts()
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Review schedule conflicts")
            }

            Button {
                isCreatingTask = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add task")
        }
        .padding(.horizontal, 18)
    }

    private func taskSection(
        title: String,
        tasks: [TodoTask],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
                .tracking(0.8)
                .padding(.horizontal, 18)

            if tasks.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private func taskRow(_ task: TodoTask) -> some View {
        HStack(spacing: 9) {
            Button {
                complete(task)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            if let category = task.category {
                Circle()
                    .fill(category.color.swiftUIColor)
                    .frame(width: 7, height: 7)
                    .help(category.name)
            }

            Button {
                editingTask = task
            } label: {
                HStack {
                    Text(task.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
    }

    private func complete(_ task: TodoTask) {
        task.setCompleted(true)

        do {
            try modelContext.save()
            CompletionFeedbackPlayer.playTaskCompletedSound()
        } catch {
            assertionFailure("Unable to complete notch task: \(error)")
        }
    }

    private func refreshPlanState() {
        do {
            appliedPlan = try PlannerCoordinator.replan(in: modelContext)
        } catch {
            plannerError = error.localizedDescription
        }
    }

    private func reviewConflicts() {
        if appliedPlan?.output.conflicts.isEmpty == false {
            isPlanUpdatePresented = true
        } else {
            refreshPlanState()

            if appliedPlan?.output.conflicts.isEmpty == false {
                isPlanUpdatePresented = true
            }
        }
    }

    private func undoLastPlan() {
        guard let snapshot = appliedPlan?.undoSnapshot else { return }

        do {
            try PlannerCoordinator.undo(snapshot, in: modelContext)
            appliedPlan = nil
        } catch {
            plannerError = error.localizedDescription
        }
    }
}
