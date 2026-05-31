import Foundation
import SwiftUI

@MainActor
class GoogleTasksService: ObservableObject {
    @Published var taskLists: [TaskList] = []
    @Published var tasks: [String: [GTask]] = [:]  // listId -> tasks
    @Published var isLoading = false
    @Published var error: String?

    var authService: AuthService?

    private let baseURL = "https://tasks.googleapis.com/tasks/v1"

    // MARK: - Task Lists

    func fetchTaskLists() async {
        guard let token = await authService?.validAccessToken() else { return }
        isLoading = true
        error = nil

        do {
            let data = try await get("/users/@me/lists", token: token)
            let response = try JSONDecoder().decode(TaskListResponse.self, from: data)
            taskLists = response.items ?? []

            // Fetch tasks for all lists
            await withTaskGroup(of: Void.self) { group in
                for list in taskLists {
                    group.addTask { await self.fetchTasks(for: list.id) }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func fetchTasks(for listId: String) async {
        guard let token = await authService?.validAccessToken() else { return }

        do {
            let data = try await get("/lists/\(listId)/tasks?showCompleted=false&maxResults=100", token: token)
            let response = try JSONDecoder().decode(TasksResponse.self, from: data)
            let items = (response.items ?? []).map { item -> GTask in
                var t = item
                t.listId = listId
                return t
            }
            tasks[listId] = items
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A task plus its nesting depth, ready for rendering.
    struct OrderedTask: Identifiable {
        let task: GTask
        let isChild: Bool
        var id: String { task.id }
    }

    /// How tasks are ordered within a view.
    enum SortOrder: String, CaseIterable {
        case myOrder, dueDate, title

        var label: String {
            switch self {
            case .myOrder: return "My order"
            case .dueDate: return "Due date"
            case .title:   return "Title"
            }
        }
        var icon: String {
            switch self {
            case .myOrder: return "line.3.horizontal"
            case .dueDate: return "calendar"
            case .title:   return "textformat"
            }
        }
    }

    @Published var sortOrder: SortOrder = .myOrder

    /// Returns the list's tasks in display order, honoring `sortOrder`.
    /// Only "My order" nests subtasks under parents; the other sorts flatten.
    func orderedTasks(for listId: String) -> [OrderedTask] {
        let all = tasks[listId] ?? []

        if sortOrder != .myOrder {
            let sorted = all.sorted(by: comparator)
            return sorted.map { OrderedTask(task: $0, isChild: false) }
        }

        let parents = all.filter { !$0.isSubtask }.sorted { ($0.position ?? "") < ($1.position ?? "") }
        let childrenByParent = Dictionary(grouping: all.filter { $0.isSubtask }) { $0.parent ?? "" }

        var result: [OrderedTask] = []
        for parent in parents {
            result.append(OrderedTask(task: parent, isChild: false))
            let children = (childrenByParent[parent.id] ?? []).sorted { ($0.position ?? "") < ($1.position ?? "") }
            for child in children {
                result.append(OrderedTask(task: child, isChild: true))
            }
        }
        // Orphaned subtasks (parent completed/missing) — show at the end so nothing disappears
        let shownIds = Set(result.map(\.id))
        for task in all where !shownIds.contains(task.id) {
            result.append(OrderedTask(task: task, isChild: task.isSubtask))
        }
        return result
    }

    /// Shared comparator for due/title sorts (tasks without a due date sort last).
    private func comparator(_ a: GTask, _ b: GTask) -> Bool {
        switch sortOrder {
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .dueDate:
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return a.title < b.title
            }
        case .myOrder:
            return (a.position ?? "") < (b.position ?? "")
        }
    }

    // MARK: - Task CRUD

    func addTask(title: String, notes: String? = nil, due: Date? = nil, to listId: String) async {
        guard let token = await authService?.validAccessToken() else { return }

        var body: [String: Any] = ["title": title]
        if let notes { body["notes"] = notes }
        if let due {
            let formatter = ISO8601DateFormatter()
            body["due"] = formatter.string(from: due)
        }

        do {
            let data = try await post("/lists/\(listId)/tasks", body: body, token: token)
            var newTask = try JSONDecoder().decode(GTask.self, from: data)
            newTask.listId = listId
            tasks[listId, default: []].insert(newTask, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func completeTask(_ task: GTask) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        let body: [String: Any] = ["status": "completed"]

        do {
            _ = try await patch("/lists/\(listId)/tasks/\(task.id)", body: body, token: token)
            tasks[listId]?.removeAll { $0.id == task.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteTask(_ task: GTask) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        do {
            try await delete("/lists/\(listId)/tasks/\(task.id)", token: token)
            tasks[listId]?.removeAll { $0.id == task.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTask(_ task: GTask, title: String, notes: String?) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        var body: [String: Any] = ["title": title]
        body["notes"] = notes ?? ""

        do {
            let data = try await patch("/lists/\(listId)/tasks/\(task.id)", body: body, token: token)
            var updated = try JSONDecoder().decode(GTask.self, from: data)
            updated.listId = listId
            if let idx = tasks[listId]?.firstIndex(where: { $0.id == task.id }) {
                tasks[listId]?[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Set or clear a task's due date. Pass nil to clear.
    func setDueDate(_ task: GTask, to date: Date?) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        var body: [String: Any] = [:]
        if let date {
            // Google stores date-only at midnight UTC
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            let utcMidnight = Calendar.current.startOfDay(for: date)
            body["due"] = f.string(from: utcMidnight)
        } else {
            body["due"] = NSNull()
        }

        do {
            let data = try await patch("/lists/\(listId)/tasks/\(task.id)", body: body, token: token)
            var updated = try JSONDecoder().decode(GTask.self, from: data)
            updated.listId = listId
            if let idx = tasks[listId]?.firstIndex(where: { $0.id == task.id }) {
                tasks[listId]?[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Add a subtask under a parent task.
    func addSubtask(to parent: GTask, title: String) async {
        guard let listId = parent.listId,
              let token = await authService?.validAccessToken() else { return }

        do {
            let data = try await post("/lists/\(listId)/tasks?parent=\(parent.id)", body: ["title": title], token: token)
            var newTask = try JSONDecoder().decode(GTask.self, from: data)
            newTask.listId = listId
            tasks[listId, default: []].append(newTask)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Move a task to a different list (Google Tasks `move` with destinationTasklist).
    func moveTask(_ task: GTask, toList destinationId: String) async {
        guard let listId = task.listId, listId != destinationId,
              let token = await authService?.validAccessToken() else { return }

        do {
            let data = try await post("/lists/\(listId)/tasks/\(task.id)/move?destinationTasklist=\(destinationId)", body: [:], token: token)
            var moved = try JSONDecoder().decode(GTask.self, from: data)
            moved.listId = destinationId
            tasks[listId]?.removeAll { $0.id == task.id }
            tasks[destinationId, default: []].append(moved)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Selection & Smart Views

    /// What the user is currently viewing.
    enum Selection: Hashable {
        case all
        case today
        case upcoming
        case list(String)   // listId

        /// True for the aggregated smart views (→ show list badges).
        var isSmart: Bool {
            if case .list = self { return false }
            return true
        }

        var icon: String {
            switch self {
            case .all:      return "tray.full"
            case .today:    return "sun.max"
            case .upcoming: return "calendar"
            case .list:     return "list.bullet"
            }
        }

        /// Compact, persistable token. Lists serialize as `list:<id>`.
        var storageKey: String {
            switch self {
            case .all:          return "all"
            case .today:        return "today"
            case .upcoming:     return "upcoming"
            case .list(let id): return "list:" + id
            }
        }

        /// Rebuild from a `storageKey`, falling back to `.all` if a saved list
        /// no longer exists or `.today` for an unknown token.
        init(storageKey: String, lists: [TaskList]) {
            if storageKey.hasPrefix("list:") {
                let id = String(storageKey.dropFirst(5))
                self = lists.contains { $0.id == id } ? .list(id) : .all
            } else {
                switch storageKey {
                case "all":      self = .all
                case "upcoming": self = .upcoming
                default:         self = .today
                }
            }
        }
    }

    var allTasks: [GTask] {
        tasks.values.flatMap { $0 }
    }

    /// Tasks across every list whose title or notes match `query`.
    func search(_ query: String) -> [OrderedTask] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return allTasks
            .filter { $0.title.localizedCaseInsensitiveContains(q)
                   || ($0.notes?.localizedCaseInsensitiveContains(q) ?? false) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { OrderedTask(task: $0, isChild: false) }
    }

    /// Returns the rows to display for a given selection.
    /// - Single list  → nested parent/child, in server order.
    /// - Smart views  → flat, sorted by due date, each carrying its list badge.
    func rows(for selection: Selection) -> [OrderedTask] {
        switch selection {
        case .list(let id):
            return orderedTasks(for: id)
        case .all:
            return smartRows { _ in true }
        case .today:
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            return smartRows { due in due != nil && due! < tomorrow }   // overdue + today
        case .upcoming:
            return smartRows { due in due != nil }
        }
    }

    /// Flat, due-sorted rows across all lists, filtered by a due-date predicate.
    private func smartRows(_ includeDue: (Date?) -> Bool) -> [OrderedTask] {
        let filtered = allTasks.filter { includeDue($0.due) }
        let sorted = filtered.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return a.title < b.title
            }
        }
        return sorted.map { OrderedTask(task: $0, isChild: false) }
    }

    // MARK: - List helpers

    func listTitle(for id: String?) -> String? {
        guard let id else { return nil }
        return taskLists.first { $0.id == id }?.title
    }

    /// A stable color per list, derived from its position in the list array.
    func listColor(for id: String?) -> Color {
        let palette: [Color] = [
            Color(hex: "F0A830"), Color(hex: "5BB8A5"), Color(hex: "8C7AE6"),
            Color(hex: "E5709B"), Color(hex: "5B9BD5"), Color(hex: "E5604D"),
        ]
        guard let id, let idx = taskLists.firstIndex(where: { $0.id == id }) else {
            return Color.secondary
        }
        return palette[idx % palette.count]
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func post(_ path: String, body: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func patch(_ path: String, body: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    @discardableResult
    private func delete(_ path: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    /// Performs the request and throws a readable error on non-2xx responses,
    /// extracting Google's API error message when present.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }

        if !(200...299).contains(http.statusCode) {
            throw APIError.from(statusCode: http.statusCode, data: data)
        }
        return data
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }

    /// Build a friendly message from Google's error JSON.
    static func from(statusCode: Int, data: Data) -> APIError {
        struct GoogleError: Decodable {
            struct Inner: Decodable {
                let message: String?
                let status: String?
                struct Detail: Decodable { let reason: String? }
                let details: [Detail]?
            }
            let error: Inner?
        }

        if let decoded = try? JSONDecoder().decode(GoogleError.self, from: data),
           let inner = decoded.error {
            // Special-case the most common setup error
            let reasons = (inner.details ?? []).compactMap { $0.reason }
            if reasons.contains("SERVICE_DISABLED") {
                return .message("Google Tasks API isn't enabled for this project yet. Enable it in Google Cloud Console, wait a minute, then refresh.")
            }
            if let msg = inner.message {
                return .message(msg)
            }
        }
        return .message("Request failed (HTTP \(statusCode))")
    }
}
