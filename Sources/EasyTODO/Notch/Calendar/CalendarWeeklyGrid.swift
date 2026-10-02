import SwiftUI

struct CalendarWeeklyGrid: View {
    let schedule: WeeklySchoolSchedule
    let categories: [TaskCategory]
    let settings: SchoolScheduleStore
    let columnWidth: CGFloat
    let onNavigate: (Int) -> Void
    let onCategoryChange: (CalendarGlanceEvent, UUID?) -> Void
    @State private var schoolHover = CalendarSchoolDayHover()

    private var hoveredSchoolAction: CalendarSchoolDayHoverAction {
        guard let date = schoolHover.activeDate else { return .none }
        return CalendarSchoolDayHover.action(for: date, in: settings, calendar: schedule.calendar)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                weekChevron("chevron.left", help: "Previous week", step: -1)
                columns { day in
                    VStack(spacing: 2) {
                        Text(SchoolWeekday(rawValue: schedule.calendar.component(.weekday, from: day.date))!.title)
                            .font(.system(size: 9, weight: .semibold))
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(schedule.calendar.isDateInToday(day.date) ? 1 : 0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(schedule.calendar.isDateInToday(day.date) ? Color.white.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                    .overlay {
                        if schoolHover.activeDate == day.date,
                           hoveredSchoolAction != .none {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.06))
                                .allowsHitTesting(false)
                        }
                    }
                    .anchorPreference(key: CalendarDayHeaderAnchors.self, value: .bounds) { [day.date: $0] }
                    .onHover { inside in
                        if inside {
                            schoolHover.headerEntered(day.date, action: CalendarSchoolDayHover.action(for: day.date, in: settings, calendar: schedule.calendar))
                        } else {
                            schoolHover.headerExited(day.date)
                        }
                    }
                }

                weekChevron("chevron.right", help: "Next week", step: 1)
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(spacing: 6) {
                    columns { day in
                        Group {
                            switch day.school?.status {
                            case .noSchool: EmptyView()
                            case .pending: Text("Pending").foregroundStyle(.orange)
                            case .replacementSchoolDay(let weekday): Text("↳ \(weekday.title)").foregroundStyle(.white.opacity(0.65))
                            case .none: Text("No data").foregroundStyle(.white.opacity(0.35))
                            default: Text(" ")
                            }
                        }
                        .font(.system(size: 8, weight: .medium))
                    }

                    if schedule.days.contains(where: { !schedule.events(on: $0, in: .unplaced).isEmpty }) {
                        eventBand(.unplaced)
                    }
                    columns { day in
                        VStack(alignment: .leading, spacing: 5) {
                            classes(day, session: .beforeLunch)
                            events(day, band: .beforeLunch)
                        }
                        .frame(minHeight: 12, alignment: .topLeading)
                    }

                    if schedule.expandsLunch {
                        eventBand(.lunch)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.035))
                            .overlay(alignment: .top) { separator }
                            .overlay(alignment: .bottom) { separator }
                    } else {
                        separator.padding(.vertical, 3)
                    }

                    columns { day in
                        VStack(alignment: .leading, spacing: 5) {
                            classes(day, session: .afterLunch)
                            events(day, band: .afterLunch)
                        }
                        .frame(minHeight: 12, alignment: .topLeading)
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, 26)
        }
        .background {
            CalendarWeekSwipeView(onNavigate: onNavigate)
        }
        .overlayPreferenceValue(CalendarDayHeaderAnchors.self) { anchors in
            GeometryReader { geometry in
                if let date = schoolHover.activeDate, let anchor = anchors[date],
                   hoveredSchoolAction != .none {
                    let header = geometry[anchor]
                    let width = min(136.0, max(0, geometry.size.width - 8))
                    let left = min(max(4, header.midX - width / 2), geometry.size.width - width - 4)
                    Button {
                        schoolHover.performAction(in: settings, calendar: schedule.calendar)
                    } label: {
                        Text(hoveredSchoolAction.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(width: width, height: 26)
                            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(settings.persistenceError != nil)
                    .accessibilityLabel("\(hoveredSchoolAction.title) for \(date.formatted(date: .complete, time: .omitted))")
                    .onHover { inside in
                        if inside { schoolHover.actionEntered(date) } else { schoolHover.actionExited(date) }
                    }
                    .id(date)
                    // An in-panel overlay avoids an external popover: both the
                    // header and action stay inside the existing notch frame.
                    .position(x: left + width / 2, y: header.maxY + 2 + 13)
                }
            }
        }
        .onChange(of: schedule.days.map(\.date)) { schoolHover.dismiss() }
        .onChange(of: hoveredSchoolAction) {
            if hoveredSchoolAction == .none { schoolHover.dismiss() }
        }
        .onDisappear { schoolHover.dismiss() }
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.22)).frame(height: 0.5)
    }

    private func columns<Content: View>(@ViewBuilder content: @escaping (WeeklySchoolSchedule.Day) -> Content) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(schedule.days) { day in
                content(day).frame(width: columnWidth, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func classes(_ day: WeeklySchoolSchedule.Day, session: SchoolSession) -> some View {
        ForEach((day.school?.lessons ?? []).filter { $0.session == session }) { lesson in
            Text(lesson.course)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(width: max(0, columnWidth - 6), height: 12, alignment: .center)
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
                .background(
                    Color.white.opacity(0.10975),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .frame(width: columnWidth, alignment: .center)
                .clipped()
                .help(lesson.course)
        }
    }

    private func eventBand(_ band: SpecialEventBand) -> some View {
        columns { day in
            VStack(alignment: .leading, spacing: 5) { events(day, band: band) }
        }
    }

    private func events(_ day: WeeklySchoolSchedule.Day, band: SpecialEventBand) -> some View {
        ForEach(schedule.events(on: day, in: band)) { event in
            let color = eventColor(event)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.isAllDay ? "All day" : event.start < day.date ? "Ongoing" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 8))
                    .monospacedDigit()
                Text(event.title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(color)
            .padding(.leading, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.7)).frame(width: 1) }
            .help("\(event.title) • \(event.calendarTitle)\n\(event.start.formatted()) – \(event.end.formatted())")
            .contextMenu {
                if let key = event.mappingKey {
                    Menu("Category") {
                        Button("None") { onCategoryChange(event, nil) }
                        ForEach(categories) { category in
                            Button(category.name) { onCategoryChange(event, category.id) }
                        }
                    }
                    if !event.isAllDay {
                        Menu("Place event") {
                            Button("Automatic (configured lunch hours)") { settings.placeEvent(key, in: nil) }
                            ForEach(SpecialEventBand.allCases, id: \.self) { placement in
                                Button(placement.title) { settings.placeEvent(key, in: placement) }
                            }
                        }
                    }
                } else {
                    Text("No stable EventKit identifier available")
                }
            }
        }
    }

    private func weekChevron(_ symbol: String, help: String, step: Int) -> some View {
        Button { onNavigate(step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func eventColor(_ event: CalendarGlanceEvent) -> Color {
        CalendarEventPresentation.category(for: event, mappings: settings.preferences.eventCategories,
                                           categories: categories)?.color.swiftUIColor ?? .white.opacity(0.65)
    }
}

private struct CalendarDayHeaderAnchors: PreferenceKey {
    static var defaultValue: [Date: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [Date: Anchor<CGRect>], nextValue: () -> [Date: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}
