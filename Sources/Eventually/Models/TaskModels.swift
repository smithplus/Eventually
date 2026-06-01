import Foundation

struct TaskList: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var updated: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, updated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        if let updatedString = try container.decodeIfPresent(String.self, forKey: .updated) {
            updated = ISO8601DateFormatter().date(from: updatedString)
        }
    }
}

struct GTask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var notes: String?
    var status: TaskStatus
    var due: Date?
    var completed: Date?
    var listId: String?

    /// Parent task id — present when this task is a subtask.
    var parent: String?
    /// Server-side ordering string within the list.
    var position: String?

    var isCompleted: Bool { status == .completed }
    var isSubtask: Bool { parent != nil }

    /// Recurring metadata (computed by GoogleTasksService)
    var isRecurring: Bool = false
    var recurrencePattern: RecurrencePattern?

    enum RecurrencePattern: String, Codable {
        case daily = "Daily"
        case weekly = "Weekly"
        case biweekly = "Biweekly"
        case monthly = "Monthly"

        var icon: String {
            return "arrow.clockwise"
        }
    }

    /// Google stores `due` as a date anchored to UTC midnight. This returns the
    /// LOCAL midnight Date for that same calendar day, so comparisons against
    /// the user's local "today" land in the right day bucket.
    /// DST fix: if the local calendar can't produce midnight for this day
    /// (spring-forward gap), advance one hour to land past the gap.
    var dueDay: Date? {
        guard let due else { return nil }
        let comps = GTask.utcCalendar.dateComponents([.year, .month, .day], from: due)
        if let d = Calendar.current.date(from: comps) { return d }
        // DST gap: try 01:00 on the same day, then normalize back to start of day
        var fallback = comps
        fallback.hour = 1
        return Calendar.current.date(from: fallback).map {
            Calendar.current.startOfDay(for: $0)
        }
    }

    static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    enum TaskStatus: String, Codable {
        case needsAction = "needsAction"
        case completed = "completed"

        // Resilient decode: unknown future Google status values fall back to needsAction
        // instead of throwing and breaking the entire list fetch.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = TaskStatus(rawValue: raw) ?? .needsAction
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status, due, completed, parent, position
        // NOTE: isRecurring and recurrencePattern are intentionally excluded —
        // they are computed locally by GoogleTasksService and never stored in Google's API.
        // An explicit encode(to:) below ensures they are never serialized to any cache.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(parent, forKey: .parent)
        try container.encodeIfPresent(position, forKey: .position)
        // Dates stored as ISO8601 strings
        if let due {
            try container.encode(ISO8601DateFormatter().string(from: due), forKey: .due)
        }
        if let completed {
            try container.encode(ISO8601DateFormatter().string(from: completed), forKey: .completed)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // Google occasionally returns tasks with an empty/missing title
        title = (try container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        status = try container.decode(TaskStatus.self, forKey: .status)
        parent = try container.decodeIfPresent(String.self, forKey: .parent)
        position = try container.decodeIfPresent(String.self, forKey: .position)
        if let dueString = try container.decodeIfPresent(String.self, forKey: .due) {
            due = GTask.parseDate(dueString)
        }
        if let completedString = try container.decodeIfPresent(String.self, forKey: .completed) {
            completed = GTask.parseDate(completedString)
        }
    }

    init(id: String = UUID().uuidString, title: String, notes: String? = nil, status: TaskStatus = .needsAction, due: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.due = due
    }

    /// Google Tasks returns RFC-3339 with fractional seconds ("...T00:00:00.000Z").
    /// The default ISO8601DateFormatter rejects fractional seconds, so try both.
    /// Formatters are cached as statics — ISO8601DateFormatter() is expensive to construct.
    static func parseDate(_ string: String) -> Date? {
        if let d = isoWithFraction.date(from: string) { return d }
        return isoPlain.date(from: string)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()
}

struct TaskListResponse: Codable {
    let items: [TaskList]?
}

struct TasksResponse: Codable {
    let items: [GTask]?
}
