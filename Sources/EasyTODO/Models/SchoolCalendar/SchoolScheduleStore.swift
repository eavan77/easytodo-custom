import Foundation
import Observation
import SwiftData

// EasyTODO-owned settings; no EventKit writes and no planner side effects.
// Category UUIDs refer to live TaskCategory records; colors are never copied.
struct SchoolSchedulePreferences: Codable {
    // Legacy resolutions, migrated into SwiftData when the store is connected.
    var schoolOverrides: [SchoolDate: SchoolDayStatus] = [:]
    var baseSchoolOverrides: [SchoolDate: SchoolDayStatus]? = [:]
    var timetable: SchoolTimetable = .semester1
    var semesterEnd: SchoolDate?
    var lunchWindow: SchoolLunchWindow?
    var eventCategories: [String: UUID] = [:]
    var eventPlacements: [String: SpecialEventBand] = [:]
}

@MainActor
@Observable
final class SchoolScheduleStore {
    private(set) var preferences: SchoolSchedulePreferences
    private(set) var persistenceError: String?
    private(set) var personalOverrides: [SchoolDate: SchoolDayStatus] = [:]
    private let defaults: UserDefaults
    private var modelContext: ModelContext?
    private let key = "EasyTODO.schoolSchedule.semester1.v1"

    init(defaults: UserDefaults = .standard, modelContext: ModelContext? = nil) {
        self.defaults = defaults
        do {
            if let data = defaults.data(forKey: key) {
                preferences = try JSONDecoder().decode(SchoolSchedulePreferences.self, from: data)
            } else {
                preferences = SchoolSchedulePreferences()
            }
        } catch {
            preferences = SchoolSchedulePreferences()
            persistenceError = "Unable to read saved school settings. \(error.localizedDescription)"
        }
        if let modelContext { connectSchoolOverrides(in: modelContext) }
    }

    var baseSchoolCalendar: SchoolCalendar {
        var school = SchoolCalendar.semester1
        school.overrides.merge(preferences.baseSchoolOverrides ?? [:]) { _, imported in imported }
        school.semesterEnd = preferences.semesterEnd
        return school
    }

    var schoolCalendar: SchoolCalendar {
        var school = baseSchoolCalendar
        school.personalOverrides = personalOverrides
        return school
    }

    func effectiveSchoolStatus(for date: Date, calendar: Calendar = .current) -> SchoolDayStatus? {
        schoolCalendar.effectiveSchoolStatus(for: date, calendar: calendar)
    }

    func personalOverride(for date: SchoolDate) -> SchoolDayStatus? { personalOverrides[date] }

    // Also called on Calendar appearance/activation so another consumer's
    // persisted choices are reloaded before they are presented.
    func connectSchoolOverrides(in context: ModelContext) {
        guard persistenceError == nil else { return }
        modelContext = context
        do {
            try migrateLegacyResolutions(in: context)
            try reloadPersonalOverrides(in: context)
        } catch {
            persistenceError = "Unable to load school overrides. \(error.localizedDescription)"
        }
    }

    func resolve(_ date: SchoolDate, as resolution: SchoolDayResolution) {
        guard persistenceError == nil, let modelContext else { return }
        do {
            let existing = try modelContext.fetch(FetchDescriptor<SchoolStatusOverride>()).first { $0.dateKey == date.id }
            let record = existing ?? SchoolStatusOverride(date: date, resolution: resolution)
            let previousStatus = record.statusRawValue
            let previousWeekday = record.replacementWeekday
            if existing == nil { modelContext.insert(record) }
            record.setResolution(resolution)
            do {
                try modelContext.save()
            } catch {
                if existing == nil { modelContext.delete(record) } else {
                    record.statusRawValue = previousStatus
                    record.replacementWeekday = previousWeekday
                }
                throw error
            }
            personalOverrides[date] = resolution.status
        } catch {
            persistenceError = "Unable to save school override. \(error.localizedDescription)"
        }
    }

    func removePersonalOverride(for date: SchoolDate) {
        guard persistenceError == nil, let modelContext else { return }
        do {
            let records = try modelContext.fetch(FetchDescriptor<SchoolStatusOverride>()).filter { $0.dateKey == date.id }
            records.forEach(modelContext.delete)
            do {
                try modelContext.save()
            } catch {
                records.forEach(modelContext.insert)
                throw error
            }
            personalOverrides[date] = nil
        } catch {
            persistenceError = "Unable to remove school override. \(error.localizedDescription)"
        }
    }

    func markPending(_ date: SchoolDate) {
        update {
            var base = $0.baseSchoolOverrides ?? [:]
            base[date] = .pending
            $0.baseSchoolOverrides = base
        }
    }

    func setTimetable(_ timetable: SchoolTimetable) {
        update { $0.timetable = timetable }
    }

    func setLunchWindow(_ window: SchoolLunchWindow?) {
        update { $0.lunchWindow = window }
    }

    func setSemesterEnd(_ date: SchoolDate?) {
        update { $0.semesterEnd = date }
    }

    func mapEvent(_ key: String, to categoryID: UUID?) {
        update { $0.eventCategories[key] = categoryID }
    }

    func placeEvent(_ key: String, in band: SpecialEventBand?) {
        update { $0.eventPlacements[key] = band }
    }

    private func reloadPersonalOverrides(in context: ModelContext) throws {
        var resolved: [SchoolDate: SchoolDayStatus] = [:]
        for record in try context.fetch(FetchDescriptor<SchoolStatusOverride>()) {
            guard let status = record.status, record.dateKey == record.schoolDate.id else {
                throw CocoaError(.coderReadCorrupt)
            }
            resolved[record.schoolDate] = status
        }
        personalOverrides = resolved
    }

    private func migrateLegacyResolutions(in context: ModelContext) throws {
        guard !preferences.schoolOverrides.isEmpty else { return }
        let existing = Set(try context.fetch(FetchDescriptor<SchoolStatusOverride>()).map(\.dateKey))
        var next = preferences
        var base = next.baseSchoolOverrides ?? [:]
        var inserted: [SchoolStatusOverride] = []
        for (date, status) in preferences.schoolOverrides {
            let resolution: SchoolDayResolution
            switch status {
            case .pending:
                base[date] = .pending
                continue
            case .regularSchoolDay: resolution = .normalSchool
            case .noSchool: resolution = .noSchool
            case .replacementSchoolDay(let weekday): resolution = .useTimetable(weekday)
            }
            if !existing.contains(date.id) {
                let record = SchoolStatusOverride(date: date, resolution: resolution)
                context.insert(record)
                inserted.append(record)
            }
        }
        next.baseSchoolOverrides = base
        next.schoolOverrides = [:]
        do {
            let data = try JSONEncoder().encode(next)
            try context.save()
            // Clear legacy choices only after their SwiftData save succeeds.
            defaults.set(data, forKey: key)
            preferences = next
        } catch {
            inserted.forEach(context.delete)
            throw error
        }
    }

    private func update(_ mutation: (inout SchoolSchedulePreferences) -> Void) {
        // Do not overwrite unreadable preferences with fallback defaults.
        guard persistenceError == nil else { return }
        var next = preferences
        mutation(&next)
        do {
            let data = try JSONEncoder().encode(next)
            defaults.set(data, forKey: key)
            preferences = next
        } catch {
            persistenceError = "Unable to save school settings. \(error.localizedDescription)"
        }
    }
}
