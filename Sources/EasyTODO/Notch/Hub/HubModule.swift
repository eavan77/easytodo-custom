import Foundation

enum HubModule: String, CaseIterable, Identifiable {
    case ddl
    case calendar
    case music
    case shelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ddl:
            "DDL"
        case .calendar:
            "Calendar"
        case .music:
            "Music"
        case .shelf:
            "Shelf"
        }
    }

    var systemImage: String {
        switch self {
        case .ddl:
            "checkmark.circle"
        case .calendar:
            "calendar"
        case .music:
            "music.note"
        case .shelf:
            "tray"
        }
    }
}
