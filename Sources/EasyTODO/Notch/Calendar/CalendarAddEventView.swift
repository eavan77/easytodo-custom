import SwiftData
import SwiftUI

struct CalendarAddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    let initialDate: Date
    var onCreated: (CalendarSpecialEvent) -> Void

    @State private var title = ""
    @State private var date = Date.now
    @State private var time = Date.now
    @State private var endTime = Date.now.addingTimeInterval(3600)
    @State private var isAllDay = false
    @State private var hasEndTime = false
    @State private var categoryID: UUID?
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Special Event").font(.headline)
            Form {
                TextField("Title", text: $title).focused($titleFocused)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("All day", isOn: $isAllDay)
                if !isAllDay {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("End time", isOn: $hasEndTime)
                    if hasEndTime {
                        DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
                LabeledContent("Category") {
                    CategorySelectionControl(categories: categories, selection: $categoryID)
                }
            }
            .controlSize(.small)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear { date = initialDate; titleFocused = true }
    }

    private func save() {
        let calendar = Calendar.current
        let start = combining(date, time: time, calendar: calendar)
        let end = hasEndTime ? combining(date, time: endTime, calendar: calendar) : nil
        do {
            let event = try CalendarSpecialEvent(title: title, start: start, end: end, isAllDay: isAllDay,
                                                categoryID: categories.first { $0.id == categoryID }?.id,
                                                calendar: calendar)
            modelContext.insert(event)
            do {
                try modelContext.save()
            } catch {
                // Undo only this insertion; do not roll back unrelated app edits.
                modelContext.delete(event)
                throw error
            }
            onCreated(event)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func combining(_ date: Date, time: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: components.hour!, minute: components.minute!, second: 0, of: date)!
    }
}
