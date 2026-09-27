import SwiftUI

struct WeekPlannerView: View {
    let tasks: [TodoTask]
    let blocks: [WorkBlock]
    let templates: [DayCapacityTemplate]
    var conflictedTaskIDs: Set<UUID> = []
    var onMove: (WorkBlock, Date, Bool) -> Void
    var onToggleLock: (WorkBlock) -> Void
    var onComplete: (TodoTask) -> Void

    @State private var movedBlocks: [WorkBlock] = []
    private let calendar = Calendar.current

    private var days: [Date] {
        let start = calendar.startOfDay(for: .now)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(days, id: \.self) { day in dayCard(day) }
            }
            .padding(14)
        }
        .alert("Keep here?", isPresented: Binding(get: { !movedBlocks.isEmpty }, set: { if !$0 { movedBlocks = [] } })) {
            Button("Keep here") {
                movedBlocks.filter { !$0.locked }.forEach(onToggleLock)
                movedBlocks = []
            }
            Button("Leave movable") { movedBlocks = [] }
        } message: { Text("Lock this planned date so automatic replanning will not move it.") }
    }

    private func dayCard(_ day: Date) -> some View {
        let dayBlocks = blocks.filter {
            calendar.isDate($0.date, inSameDayAs: day) && $0.status != .done && $0.status != .skipped
        }
        let dayTasks = DayTaskPresentation.tasks(on: day, from: tasks, blocks: dayBlocks, calendar: calendar)
        let representativeByTask = Dictionary(grouping: dayBlocks, by: \.taskID).compactMapValues { group in
            group.sorted { ($0.date, $0.period.planningOrder) < ($1.date, $1.period.planningOrder) }.first
        }
        let template = templates.first { $0.weekday == calendar.component(.weekday, from: day) }

        return VStack(alignment: .leading, spacing: 10) {
            Text(day.formatted(.dateTime.weekday(.abbreviated).day())).font(.headline).textCase(.uppercase)
            Text(template?.kind.title ?? "Custom day").font(.caption).foregroundStyle(.secondary)
            Divider()
            if dayTasks.isEmpty {
                Text("Open capacity").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 18)
            }
            ForEach(dayTasks) { task in
                if let block = representativeByTask[task.id] {
                    taskCard(task, representative: block, allDayBlocks: dayBlocks)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(width: 170, alignment: .top).frame(minHeight: 270, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
        .dropDestination(for: String.self) { items, _ in
            guard let value = items.first, let id = UUID(uuidString: value),
                  let block = blocks.first(where: { $0.id == id }) else { return false }
            let sourceDay = calendar.startOfDay(for: block.date)
            let group = blocks.filter {
                $0.taskID == block.taskID && calendar.startOfDay(for: $0.date) == sourceDay
                    && $0.status != .done && $0.status != .skipped
            }
            guard !group.isEmpty, group.allSatisfy({ !$0.locked }) else { return false }
            group.forEach { onMove($0, day, false) }
            movedBlocks = group
            return true
        }
    }

    private func taskCard(_ task: TodoTask, representative block: WorkBlock, allDayBlocks: [WorkBlock]) -> some View {
        let taskBlocks = allDayBlocks.filter { $0.taskID == task.id }
        return HStack(alignment: .top, spacing: 7) {
            Button { onComplete(task) } label: {
                Image(systemName: "circle").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(task.title) complete")

            if let category = task.category {
                Circle().fill(category.color.swiftUIColor).frame(width: 6, height: 6).padding(.top, 4)
            }

            Text(task.title).font(.caption.weight(.medium)).lineLimit(3)
            Spacer(minLength: 0)
            if taskBlocks.contains(where: \.locked) {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
            if conflictedTaskIDs.contains(task.id) {
                Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(.orange)
                    .help("This task has unscheduled work")
            }
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
        .draggable(block.id.uuidString)
        .contextMenu {
            let shouldLock = !taskBlocks.allSatisfy(\.locked)
            Button(shouldLock ? "Keep here" : "Unlock planned date") {
                taskBlocks.filter { $0.locked != shouldLock }.forEach(onToggleLock)
            }
        }
    }
}
