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

struct Task: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var notes: String?
    var status: TaskStatus
    var due: Date?
    var completed: Date?
    var listId: String?

    var isCompleted: Bool { status == .completed }

    enum TaskStatus: String, Codable {
        case needsAction = "needsAction"
        case completed = "completed"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status, due, completed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        status = try container.decode(TaskStatus.self, forKey: .status)
        if let dueString = try container.decodeIfPresent(String.self, forKey: .due) {
            due = ISO8601DateFormatter().date(from: dueString)
        }
        if let completedString = try container.decodeIfPresent(String.self, forKey: .completed) {
            completed = ISO8601DateFormatter().date(from: completedString)
        }
    }

    init(id: String = UUID().uuidString, title: String, notes: String? = nil, status: TaskStatus = .needsAction, due: Date? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.due = due
    }
}

struct TaskListResponse: Codable {
    let items: [TaskList]?
}

struct TasksResponse: Codable {
    let items: [Task]?
}
