import SwiftUI

struct TaskEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: TodoTask
    let onSave: () -> Void

    @State private var workMode: WorkMode
    @State private var size: TaskSize
    @State private var blocks: Int
    @State private var energy: EnergyDemand
    @State private var uncertainty: PlanningUncertainty
    @State private var splittable: Bool
    @State private var blockMinutes: String
    @State private var minimumMinutes: String

    init(task: TodoTask, onSave: @escaping () -> Void) {
        self.task = task
        self.onSave = onSave
        _workMode = State(initialValue: task.workMode)
        _size = State(initialValue: task.taskSize)
        _blocks = State(initialValue: task.safeEstimatedBlocks)
        _energy = State(initialValue: task.energyDemand)
        _uncertainty = State(initialValue: task.uncertainty)
        _splittable = State(initialValue: task.splittable ?? true)
        let perBlock = task.estimatedMinutes.map { Int(ceil(Double($0) / Double(task.safeEstimatedBlocks))) }
        _blockMinutes = State(initialValue: perBlock.map(String.init) ?? "")
        _minimumMinutes = State(initialValue: task.minimumBlockMinutes.map(String.init) ?? "")
    }

    var body: some View {
        Form {
            Picker("Work type", selection: $workMode) {
                ForEach(WorkMode.allCases) { Text($0.title).tag($0) }
            }
            Picker("Size", selection: $size) {
                ForEach(TaskSize.allCases) { Text($0.rawValue).tag($0) }
            }
            Stepper("Estimated blocks: \(blocks)", value: $blocks, in: 1...24)
            Picker("Energy", selection: $energy) {
                ForEach(EnergyDemand.allCases) { Text($0.title).tag($0) }
            }
            Picker("Uncertainty", selection: $uncertainty) {
                ForEach(PlanningUncertainty.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Can split", isOn: $splittable)
            TextField("Block duration (optional minutes)", text: $blockMinutes)
            TextField("Minimum useful session (optional minutes)", text: $minimumMinutes)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save estimate") {
                    task.setPlanningEstimate(workMode: workMode, size: size, estimatedBlocks: blocks,
                                             energy: energy, uncertainty: uncertainty,
                                             splittable: splittable,
                                             blockMinutes: positiveInteger(blockMinutes),
                                             minimumBlockMinutes: positiveInteger(minimumMinutes))
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!validOptionalInteger(blockMinutes) || !validOptionalInteger(minimumMinutes))
            }
        }
        .formStyle(.grouped)
        .frame(width: 390, height: 440)
    }

    private func positiveInteger(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    private func validOptionalInteger(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || positiveInteger(text) != nil
    }
}
