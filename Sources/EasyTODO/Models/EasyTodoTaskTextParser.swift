import Foundation

enum ImportIssueSeverity: String, Equatable { case error = "ERROR", warning = "WARNING" }
enum ImportIssueKind: Equatable {
    case syntax, invalidField, missingTitle, unknownProject, unresolvedDependency
    case ambiguousDependency, possibleDuplicate, assessmentDeadlineMismatch, incompletePlannerMetadata, missingBlocks
}

struct ImportValidationIssue: Identifiable, Equatable {
    let id = UUID(); let severity: ImportIssueSeverity; let kind: ImportIssueKind
    let taskIndex: Int?; let line: Int?; let message: String
}

struct ParsedBlockDTO: Identifiable, Equatable {
    var id = UUID(); var name = ""; var estimatedMinutes: Int?
    var splittable = true; var minimumSessionMinutes: Int?
}

struct ParsedTaskDTO: Identifiable, Equatable {
    var id = UUID(); var title = ""; var projectName: String?; var dueDate: Date?
    var hasExplicitDueTime = false; var deadlineType: DeadlineType?; var deadlineTypeSource: DeadlineTypeSource?
    var priority: TaskPriority?; var prioritySource: PrioritySource?; var manualStartBy: Date?
    var workMode: WorkMode?; var size: TaskSize?; var estimatedBlocks: Int?; var blockMinutes: Int?
    var energy: EnergyDemand?; var uncertainty: PlanningUncertainty?; var splittable: Bool?
    var minimumBlockMinutes: Int?; var dependencyTitles: [String] = []; var relatedDate: Date?
    var notes = ""; var blocks: [ParsedBlockDTO] = []; var hasExplicitBlocks = false
}

struct TaskTextParseResult: Equatable {
    let tasks: [ParsedTaskDTO]; let issues: [ImportValidationIssue]
    var hasErrors: Bool { issues.contains { $0.severity == .error } }
}

enum EasyTodoTaskTextParser {
    private typealias Entry = (value: String, line: Int)
    private struct RawTask { var fields: [String: Entry] = [:]; var blocks: [[String: Entry]] = [] }
    private static let taskFields: Set<String> = [
        "title", "project", "due", "time", "deadline", "priority", "start_by", "work", "size", "blocks",
        "block_minutes", "energy", "uncertainty", "splittable", "min_block_minutes",
        "depends_on", "related_date", "notes"
    ]
    private static let blockFields: Set<String> = ["name", "minutes", "splittable", "min_session_minutes"]

    static func parse(_ text: String, calendar: Calendar = .current) -> TaskTextParseResult {
        let lines = text.components(separatedBy: .newlines)
        var raws: [RawTask] = []; var current: RawTask?; var currentBlock: [String: Entry]?
        var issues: [ImportValidationIssue] = []
        for (offset, rawLine) in lines.enumerated() {
            let number = offset + 1; let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.caseInsensitiveCompare("[TASK]") == .orderedSame {
                if current != nil { issues.append(issue(.error, .syntax, raws.count, number, "Nested [TASK] block.")) }
                else { current = RawTask() }
                continue
            }
            if line.caseInsensitiveCompare("[BLOCK]") == .orderedSame {
                if current == nil || currentBlock != nil {
                    issues.append(issue(.error, .syntax, raws.count, number, "[BLOCK] must be directly inside a TASK."))
                } else { currentBlock = [:] }
                continue
            }
            if line.caseInsensitiveCompare("[/BLOCK]") == .orderedSame {
                guard let completed = currentBlock, current != nil else {
                    issues.append(issue(.error, .syntax, raws.count, number, "[/BLOCK] has no matching [BLOCK].")); continue
                }
                current!.blocks.append(completed); currentBlock = nil; continue
            }
            if line.caseInsensitiveCompare("[/TASK]") == .orderedSame {
                guard let completed = current else {
                    issues.append(issue(.error, .syntax, nil, number, "[/TASK] has no matching [TASK].")); continue
                }
                if currentBlock != nil {
                    issues.append(issue(.error, .syntax, raws.count, number, "Close [BLOCK] before [/TASK].")); currentBlock = nil
                }
                raws.append(completed); current = nil; continue
            }
            guard !line.isEmpty else { continue }
            guard current != nil else {
                issues.append(issue(.error, .syntax, nil, number, "Text must be inside a [TASK] block.")); continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                issues.append(issue(.error, .syntax, raws.count, number, "Expected field: value.")); continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let allowed = currentBlock == nil ? taskFields : blockFields
            guard allowed.contains(key) else {
                issues.append(issue(.error, .invalidField, raws.count, number, "Unknown field “\(key)”.")); continue
            }
            if currentBlock != nil {
                if currentBlock![key] != nil { issues.append(issue(.error, .invalidField, raws.count, number, "Duplicate field “\(key)”.")) }
                else { currentBlock![key] = (value, number) }
            } else if current!.fields[key] != nil {
                issues.append(issue(.error, .invalidField, raws.count, number, "Duplicate field “\(key)”."))
            } else { current!.fields[key] = (value, number) }
        }
        if currentBlock != nil { issues.append(issue(.error, .syntax, raws.count, lines.count, "Missing [/BLOCK].")) }
        if current != nil { issues.append(issue(.error, .syntax, raws.count, lines.count, "Missing [/TASK].")) }
        if raws.isEmpty && issues.isEmpty { issues.append(issue(.error, .syntax, nil, nil, "No [TASK] blocks found.")) }

        var tasks: [ParsedTaskDTO] = []
        for (index, raw) in raws.enumerated() {
            let fields = raw.fields; var dto = ParsedTaskDTO()
            dto.title = fields["title"]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if dto.title.isEmpty { issues.append(issue(.error, .missingTitle, index, fields["title"]?.line, "Task title is required.")) }
            if let value = fields["project"]?.value, !isNone(value), !value.isEmpty { dto.projectName = value }
            let due = parseDate("due", fields, index, calendar, &issues); let time = parseTime(fields["time"], index, &issues)
            if let due, let time {
                var components = calendar.dateComponents([.year, .month, .day], from: due)
                components.hour = time.hour; components.minute = time.minute
                dto.dueDate = calendar.date(from: components); dto.hasExplicitDueTime = true
            } else if let due { dto.dueDate = calendar.startOfDay(for: due) }
            else if time != nil { issues.append(issue(.error, .invalidField, index, fields["time"]?.line, "A specific time requires a due date.")) }
            if let entry = fields["deadline"] {
                switch entry.value.lowercased() {
                case "official": dto.deadlineType = .hard; dto.deadlineTypeSource = .userSelected
                case "my": dto.deadlineType = .internalDeadline; dto.deadlineTypeSource = .userSelected
                case "confirm": break
                case "none": dto.deadlineType = DeadlineType.none; dto.deadlineTypeSource = .userSelected
                default: issues.append(issue(.error, .invalidField, index, entry.line, "deadline must be official, my, confirm, or none."))
                }
            }
            if let entry = fields["priority"] {
                switch entry.value.lowercased() {
                case "critical": dto.priority = .critical; dto.prioritySource = .userSelected
                case "high": dto.priority = .high; dto.prioritySource = .userSelected
                case "normal": dto.priority = .normal; dto.prioritySource = .userSelected
                case "low": dto.priority = .low; dto.prioritySource = .userSelected
                case "auto": break
                default: issues.append(issue(.error, .invalidField, index, entry.line, "priority must be critical, high, normal, low, or auto."))
                }
            }
            if let entry = fields["start_by"], entry.value.lowercased() != "auto" {
                dto.manualStartBy = parseDate("start_by", fields, index, calendar, &issues)
            }
            dto.workMode = parseEnum("work", fields, index, ["deep": .deep, "medium": .medium, "fragmentable": .fragmentable], &issues)
            dto.size = parseEnum("size", fields, index, ["s": .small, "m": .medium, "l": .large, "xl": .extraLarge], &issues)
            dto.estimatedBlocks = positive("blocks", fields, index, false, &issues)
            dto.blockMinutes = positive("block_minutes", fields, index, true, &issues)
            dto.energy = parseEnum("energy", fields, index, ["low": .low, "medium": .medium, "high": .high], &issues)
            dto.uncertainty = parseEnum("uncertainty", fields, index, ["low": .low, "medium": .medium, "high": .high], &issues)
            dto.splittable = yesNo("splittable", fields, index, &issues)
            dto.minimumBlockMinutes = positive("min_block_minutes", fields, index, true, &issues)
            if let value = fields["depends_on"]?.value, !isNone(value) {
                dto.dependencyTitles = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            dto.relatedDate = parseDate("related_date", fields, index, calendar, &issues); dto.notes = fields["notes"]?.value ?? ""

            dto.hasExplicitBlocks = !raw.blocks.isEmpty
            for blockFields in raw.blocks {
                var block = ParsedBlockDTO(); block.name = blockFields["name"]?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if block.name.isEmpty { issues.append(issue(.error, .missingTitle, index, blockFields["name"]?.line, "Block name is required.")) }
                block.estimatedMinutes = positive("minutes", blockFields, index, true, &issues)
                block.splittable = yesNo("splittable", blockFields, index, &issues) ?? true
                block.minimumSessionMinutes = positive("min_session_minutes", blockFields, index, true, &issues)
                if let total = block.estimatedMinutes, let minimum = block.minimumSessionMinutes, minimum > total {
                    issues.append(issue(.error, .invalidField, index, blockFields["min_session_minutes"]?.line,
                                        "min_session_minutes cannot exceed Block minutes."))
                }
                dto.blocks.append(block)
            }
            if dto.hasExplicitBlocks && ["blocks", "block_minutes", "splittable", "min_block_minutes"].contains(where: { fields[$0] != nil }) {
                issues.append(issue(.error, .invalidField, index, nil, "V2 BLOCK sections cannot be combined with V1 block fields."))
            }
            if !dto.hasExplicitBlocks {
                let count = dto.estimatedBlocks ?? 0
                dto.blocks = (0..<count).map { number in
                    ParsedBlockDTO(name: "Block \(number + 1)", estimatedMinutes: dto.blockMinutes,
                                   splittable: dto.splittable ?? true,
                                   minimumSessionMinutes: dto.minimumBlockMinutes)
                }
                if count == 0 { issues.append(issue(.warning, .missingBlocks, index, nil, "No explicit blocks. EasyTODO will estimate task structure.")) }
            }
            if dto.workMode == nil || dto.size == nil || dto.energy == nil || dto.uncertainty == nil || dto.blocks.isEmpty {
                issues.append(issue(.warning, .incompletePlannerMetadata, index, nil, "Planning metadata is incomplete; compatibility defaults will be used."))
            }
            tasks.append(dto)
        }
        return TaskTextParseResult(tasks: tasks, issues: issues)
    }

    private static func parseDate(_ key: String, _ fields: [String: Entry], _ index: Int,
                                  _ calendar: Calendar, _ issues: inout [ImportValidationIssue]) -> Date? {
        guard let entry = fields[key], !isNone(entry.value) else { return nil }
        let p = entry.value.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
              calendar.component(.year, from: date) == y, calendar.component(.month, from: date) == m,
              calendar.component(.day, from: date) == d else {
            issues.append(issue(.error, .invalidField, index, entry.line, "\(key) must be a valid YYYY-MM-DD date or none.")); return nil
        }
        return calendar.startOfDay(for: date)
    }
    private static func parseTime(_ entry: Entry?, _ index: Int, _ issues: inout [ImportValidationIssue]) -> (hour: Int, minute: Int)? {
        guard let entry, !isNone(entry.value) else { return nil }; let p = entry.value.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, p[0].count == 2, p[1].count == 2, let h = Int(p[0]), let m = Int(p[1]),
              (0...23).contains(h), (0...59).contains(m) else {
            issues.append(issue(.error, .invalidField, index, entry.line, "time must be a valid HH:mm value or none.")); return nil
        }; return (h, m)
    }
    private static func positive(_ key: String, _ fields: [String: Entry], _ index: Int, _ auto: Bool,
                                 _ issues: inout [ImportValidationIssue]) -> Int? {
        guard let entry = fields[key] else { return nil }; if auto && entry.value.lowercased() == "auto" { return nil }
        guard let value = Int(entry.value), value > 0 else {
            issues.append(issue(.error, .invalidField, index, entry.line, "\(key) must be a positive integer\(auto ? " or auto" : "").")); return nil
        }; return value
    }
    private static func yesNo(_ key: String, _ fields: [String: Entry], _ index: Int,
                              _ issues: inout [ImportValidationIssue]) -> Bool? {
        guard let entry = fields[key] else { return nil }
        switch entry.value.lowercased() { case "yes": return true; case "no": return false
        default: issues.append(issue(.error, .invalidField, index, entry.line, "\(key) must be yes or no.")); return nil }
    }
    private static func parseEnum<T>(_ key: String, _ fields: [String: Entry], _ index: Int,
                                     _ mapping: [String: T], _ issues: inout [ImportValidationIssue]) -> T? {
        guard let entry = fields[key] else { return nil }; guard let value = mapping[entry.value.lowercased()] else {
            issues.append(issue(.error, .invalidField, index, entry.line, "Invalid \(key) value “\(entry.value)”.")); return nil
        }; return value
    }
    private static func isNone(_ value: String) -> Bool { value.caseInsensitiveCompare("none") == .orderedSame }
    private static func issue(_ severity: ImportIssueSeverity, _ kind: ImportIssueKind, _ task: Int?, _ line: Int?, _ message: String) -> ImportValidationIssue {
        ImportValidationIssue(severity: severity, kind: kind, taskIndex: task, line: line, message: message)
    }
}
