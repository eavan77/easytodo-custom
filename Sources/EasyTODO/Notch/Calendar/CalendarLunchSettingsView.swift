import SwiftUI

struct CalendarLunchSettingsView: View {
    let settings: SchoolScheduleStore
    @State private var start = ""
    @State private var end = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lunch placement").font(.headline)
            Text("Set school lunch hours to place timed events automatically. Without them, events stay separate from classes. Right-click an event to place it at lunch explicitly.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Start HH:mm", text: $start)
                TextField("End HH:mm", text: $end)
            }
            HStack {
                Button("Save") {
                    guard let first = minutes(start), let last = minutes(end),
                          let window = SchoolLunchWindow(startMinute: first, endMinute: last) else {
                        error = "Enter a valid start and later end in 24-hour HH:mm format."
                        return
                    }
                    settings.setLunchWindow(window)
                    error = nil
                }
                Button("Clear") {
                    settings.setLunchWindow(nil)
                    start = ""
                    end = ""
                    error = nil
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Semester 1 • Winter holiday begins Jan 25, 2027. No Semester 2 rules are configured.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 290)
        .onAppear {
            if let window = settings.preferences.lunchWindow {
                start = clock(window.startMinute)
                end = clock(window.endMinute)
            }
        }
    }

    private func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
