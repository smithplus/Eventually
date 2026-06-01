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
    var dueDay: Date? {
        guard let due else { return nil }
        let comps = GTask.utcCalendar.dateComponents([.year, .month, .day], from: due)
        return Calendar.current.date(from: comps)
    }

    static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    enum TaskStatus: String, Codable {
        case needsAction = "needsAction"
        case completed = "completed"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status, due, completed, parent, position
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
    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }
        return ISO8601DateFormatter().date(from: string)
    }
}

struct TaskListResponse: Codable {
    let items: [TaskList]?
}

struct TasksResponse: Codable {
    let items: [GTask]?
}
