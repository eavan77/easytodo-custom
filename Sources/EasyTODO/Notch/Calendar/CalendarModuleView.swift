import AppKit
import EventKit
import SwiftData
import SwiftUI

struct CalendarModuleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskCategory.sortOrder) private var categories: [TaskCategory]
    @Query private var localEvents: [CalendarSpecialEvent]
    @State private var provider = CalendarEventProvider()
    @State private var settings = SchoolScheduleStore()
    @State private var navigation = CalendarWeekNavigation()
    @State private var referenceDate = Date.now
    @State private var activeSheet: CalendarSheet?
    @State private var saveError: String?

    private enum CalendarSheet: String, Identifiable {
        case addEvent, lunchSettings, externalCalendars
        var id: String { rawValue }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private var week: CalendarWeek { navigation.week(calendar: calendar) }

    private var schedule: WeeklySchoolSchedule {
        let external: [CalendarGlanceEvent]
        if case .granted(let snapshot) = provider.state, snapshot.range == week.interval {
            external = snapshot.events
        } else {
            external = []
        }
        let events = CalendarEventPresentation.merged(local: localEvents, external: external, range: week.interval)
        return WeeklySchoolSchedule(week: week, school: settings.schoolCalendar,
                                   timetable: settings.preferences.timetable, events: events,
                                   calendar: calendar, lunchWindow: settings.preferences.lunchWindow,
                                   placements: settings.preferences.eventPlacements)
    }

    private var pendingDates: [SchoolDate] {
        let today = SchoolDate(referenceDate, calendar: calendar)
        let upcomingEnd = SchoolDate(calendar.date(byAdding: .day, value: 14, to: referenceDate)!, calendar: calendar)
        let upcoming = settings.schoolCalendar.pendingDates(from: today, through: upcomingEnd)
        return Set(schedule.pendingDates + upcoming).sorted()
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geometry in
                CalendarWeeklyGrid(schedule: schedule, categories: categories, settings: settings,
                                   columnWidth: max(0, (geometry.size.width - 76) / 7),
                                   onNavigate: navigate, onCategoryChange: changeCategory)
            }
            footer
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addEvent:
                CalendarAddEventView(initialDate: week.interval.contains(.now) ? .now : week.days[0]) { event in
                    navigation.show(event.start, calendar: calendar)
                    refresh()
                }
            case .lunchSettings:
                VStack(spacing: 0) {
                    CalendarLunchSettingsView(settings: settings)
                    Button("Done") { activeSheet = nil }
                        .keyboardShortcut(.cancelAction)
                        .padding(.bottom, 12)
                }
            case .externalCalendars:
                VStack(spacing: 12) {
                    accessContent
                    Button("Done") { activeSheet = nil }.keyboardShortcut(.cancelAction)
                }
                .padding(16)
                .frame(width: 300)
            }
        }
        .alert("Unable to Save Event Category", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in refresh() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in refresh() }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Button("Today") {
                navigation.showToday()
                refresh()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .frame(height: 24)
            .help("Current week. Right-click for external calendars and lunch settings.")
            .contextMenu {
                Button("External calendars…") { activeSheet = .externalCalendars }
                Button("Lunch settings…") { activeSheet = .lunchSettings }
            }
            if !pendingDates.isEmpty { pendingWarning }
            if let error = settings.persistenceError {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .help(error)
                    .accessibilityLabel(error)
            }
            accessIndicator
            Spacer(minLength: 0)
            Button { activeSheet = .addEvent } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add special event")
            .accessibilityLabel("Add special event")
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 18)
        .padding(.bottom, 5)
    }

    private var pendingWarning: some View {
        Menu {
            ForEach(pendingDates) { date in
                Menu("\(date.id) — confirm school status") {
                    Button("Normal school") { settings.resolve(date, as: .normalSchool) }
                    Button("No school") { settings.resolve(date, as: .noSchool) }
                    Menu("Use another weekday's timetable") {
                        ForEach(SchoolWeekday.allCases, id: \.self) { weekday in
                            Button(weekday.title) { settings.resolve(date, as: .useTimetable(weekday)) }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .frame(width: 24, height: 24)
        .help("Confirm school status: \(pendingDates.map(\.id).joined(separator: ", "))")
        .accessibilityLabel("Unresolved school dates: \(pendingDates.map(\.id).joined(separator: ", "))")
    }

    @ViewBuilder
    private var accessIndicator: some View {
        switch provider.state {
        case .denied, .restricted, .writeOnly, .error:
            Button { activeSheet = .externalCalendars } label: {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("External calendar access needs attention")
            .accessibilityLabel("External calendar access needs attention")
        case .loading:
            ProgressView().controlSize(.mini).frame(width: 14, height: 14)
                .help("Loading external events")
        case .notDetermined, .granted:
            EmptyView()
        }
    }

    @ViewBuilder
    private var accessContent: some View {
        switch provider.state {
        case .notDetermined:
            message("Add special events from your macOS calendars. School classes and local events are available without calendar access.", action: "Allow Calendar Access") {
                Task { await provider.requestAccess() }
            }
        case .denied:
            message("Allow full access in System Settings → Privacy & Security → Calendars.", action: "Open Settings", perform: openSettings)
        case .restricted:
            message("Calendar access is restricted by this Mac's settings or administrator.", action: "Check Again") { refresh() }
        case .writeOnly:
            message("Reading external events requires full calendar access.", action: "Allow Full Access") {
                Task { await provider.requestAccess() }
            }
        case .loading:
            ProgressView("Loading external events…").controlSize(.small)
        case .error(let description):
            message(description, action: "Try Again") { refresh() }
        case .granted:
            Text("External events are connected through macOS Calendar. Right-click an event to choose an EasyTODO category or lunch placement.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func message(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform).controlSize(.small)
        }
    }

    private func navigate(_ step: Int) {
        navigation.move(by: step, calendar: calendar)
        refresh()
    }

    private func refresh() {
        settings.connectSchoolOverrides(in: modelContext)
        referenceDate = .now
        navigation.refresh(now: referenceDate)
        provider.refresh(week: week)
    }

    private func changeCategory(_ event: CalendarGlanceEvent, to categoryID: UUID?) {
        switch event.source {
        case .eventKit:
            if let key = event.mappingKey { settings.mapEvent(key, to: categoryID) }
        case .easyTODO(let id):
            guard let local = localEvents.first(where: { $0.id == id }) else { return }
            let previous = local.categoryID
            local.categoryID = categoryID
            do { try modelContext.save() } catch {
                local.categoryID = previous
                saveError = error.localizedDescription
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
