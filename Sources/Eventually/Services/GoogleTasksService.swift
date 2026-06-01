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
            applyLocalOrder()

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

    // MARK: - List CRUD

    func createList(title: String) async {
        guard let token = await authService?.validAccessToken() else { return }
        do {
            let data = try await post("/users/@me/lists", body: ["title": title], token: token)
            let list = try JSONDecoder().decode(TaskList.self, from: data)
            taskLists.append(list)
            tasks[list.id] = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func renameList(_ list: TaskList, to title: String) async {
        guard let token = await authService?.validAccessToken() else { return }
        do {
            let data = try await patch("/users/@me/lists/\(list.id)", body: ["title": title], token: token)
            let updated = try JSONDecoder().decode(TaskList.self, from: data)
            if let idx = taskLists.firstIndex(where: { $0.id == list.id }) {
                taskLists[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteList(_ list: TaskList) async {
        guard let token = await authService?.validAccessToken() else { return }
        do {
            try await delete("/users/@me/lists/\(list.id)", token: token)
            taskLists.removeAll { $0.id == list.id }
            tasks[list.id] = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Reorder a list locally (the API doesn't expose list ordering). The order
    /// is persisted and reapplied on every fetch.
    func moveList(_ list: TaskList, by offset: Int) {
        guard let idx = taskLists.firstIndex(where: { $0.id == list.id }) else { return }
        let target = idx + offset
        guard target >= 0, target < taskLists.count else { return }
        taskLists.swapAt(idx, target)
        UserDefaults.standard.set(taskLists.map(\.id), forKey: DefaultsKey.listOrder)
    }

    func canMoveList(_ list: TaskList, by offset: Int) -> Bool {
        guard let idx = taskLists.firstIndex(where: { $0.id == list.id }) else { return false }
        let target = idx + offset
        return target >= 0 && target < taskLists.count
    }

    private func applyLocalOrder() {
        let order = UserDefaults.standard.stringArray(forKey: DefaultsKey.listOrder) ?? []
        guard !order.isEmpty else { return }
        taskLists.sort {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }
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

    /// Re-sync one list from the server. Used after a mutation whose response
    /// failed to decode (the server may have applied it) so local state can't
    /// silently diverge from the server.
    private func reconcile(_ listId: String) async {
        await fetchTasks(for: listId)
    }

    /// Drop all cached data (e.g. on sign-out) so nothing stale lingers.
    func clearCache() {
        taskLists = []
        tasks = [:]
        error = nil
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

    @Published var sortOrder: SortOrder = SortOrder(
        rawValue: UserDefaults.standard.string(forKey: DefaultsKey.sortOrder) ?? ""
    ) ?? .myOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: DefaultsKey.sortOrder) }
    }

    /// Returns the list's tasks in display order, honoring `sortOrder`.
    /// Only "My order" nests subtasks under parents; the other sorts flatten.
    func orderedTasks(for listId: String) -> [OrderedTask] {
        let all = tasks[listId] ?? []

        if sortOrder != .myOrder {
            let sorted = all.sorted { comparator($0, $1, order: sortOrder) }
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
    private func comparator(_ a: GTask, _ b: GTask, order: SortOrder) -> Bool {
        switch order {
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .dueDate:
            switch (a.dueDay, b.dueDay) {
            case let (x?, y?): return x < y
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
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
        if let due { body["due"] = Self.encodeDue(due) }

        do {
            let data = try await post("/lists/\(listId)/tasks", body: body, token: token)
            var newTask = try JSONDecoder().decode(GTask.self, from: data)
            newTask.listId = listId
            tasks[listId, default: []].insert(newTask, at: 0)
        } catch {
            self.error = error.localizedDescription
            await reconcile(listId)
        }
    }

    /// Encode a picked calendar day as UTC-midnight RFC-3339 (Google's date-only
    /// convention), taking the day from the user's LOCAL calendar so the day
    /// the user picked is the day Google stores — regardless of timezone.
    static func encodeDue(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let utcMidnight = GTask.utcCalendar.date(from: comps) ?? date
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: utcMidnight)
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
            await reconcile(listId)
        }
    }

    /// Set or clear a task's due date. Pass nil to clear.
    func setDueDate(_ task: GTask, to date: Date?) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        var body: [String: Any] = [:]
        body["due"] = date.map(Self.encodeDue) ?? NSNull()

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
            await reconcile(listId)
            await reconcile(destinationId)
        }
    }

    // MARK: - Batch operations (multi-select)

    func completeTasks(_ items: [GTask]) async {
        for task in items { await completeTask(task) }
    }

    func deleteTasks(_ items: [GTask]) async {
        for task in items { await deleteTask(task) }
    }

    func setDueDate(_ items: [GTask], to date: Date?) async {
        for task in items { await setDueDate(task, to: date) }
    }

    func moveTasks(_ items: [GTask], toList destinationId: String) async {
        for task in items { await moveTask(task, toList: destinationId) }
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

    /// A run of rows that belong to the same list, with its header info.
    struct ListGroup: Identifiable {
        let listId: String
        let title: String
        let rows: [OrderedTask]
        var id: String { listId }
    }

    /// A run of rows sharing a date bucket (Overdue/Today/…).
    struct DateGroup: Identifiable {
        let key: String
        let title: String
        let rows: [OrderedTask]
        var id: String { key }
    }

    /// Group already-ordered rows into date buckets: Overdue, Today, Tomorrow,
    /// This week, Later, No date — in that fixed order.
    func groupedByDate(_ rows: [OrderedTask]) -> [DateGroup] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let weekEnd = cal.date(byAdding: .day, value: 7, to: today) ?? today

        var buckets: [String: [OrderedTask]] = [:]
        for row in rows {
            let key: String
            if let day = row.task.dueDay {
                if day < today { key = "overdue" }
                else if day == today { key = "today" }
                else if day == tomorrow { key = "tomorrow" }
                else if day < weekEnd { key = "week" }
                else { key = "later" }
            } else {
                key = "none"
            }
            buckets[key, default: []].append(row)
        }

        let order: [(String, String)] = [
            ("overdue", "Overdue"), ("today", "Today"), ("tomorrow", "Tomorrow"),
            ("week", "This week"), ("later", "Later"), ("none", "No date"),
        ]
        return order.compactMap { key, title in
            guard let r = buckets[key], !r.isEmpty else { return nil }
            return DateGroup(key: key, title: title, rows: r)
        }
    }

    /// Group already-ordered rows by their list, preserving the list ordering.
    func grouped(_ rows: [OrderedTask]) -> [ListGroup] {
        let byList = Dictionary(grouping: rows) { $0.task.listId ?? "" }
        return taskLists.compactMap { list in
            guard let r = byList[list.id], !r.isEmpty else { return nil }
            return ListGroup(listId: list.id, title: list.title, rows: r)
        }
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
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            return smartRows { day in day != nil && day! < tomorrow }   // overdue + today
        case .upcoming:
            return smartRows { day in day != nil }
        }
    }

    /// Flat rows across all lists, filtered by a (local) due-day predicate and
    /// ordered by the active sort. `myOrder` isn't meaningful across lists, so it
    /// falls back to due-date ordering for the smart views.
    private func smartRows(_ includeDay: (Date?) -> Bool) -> [OrderedTask] {
        let filtered = allTasks.filter { includeDay($0.dueDay) }
        let order: SortOrder = (sortOrder == .myOrder) ? .dueDate : sortOrder
        let sorted = filtered.sorted { comparator($0, $1, order: order) }
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
    /// extracting Google's API error message when present. A request that
    /// reaches a 2xx clears any stale error banner; failures re-set it via the
    /// caller's catch.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }

        if !(200...299).contains(http.statusCode) {
            throw APIError.from(statusCode: http.statusCode, data: data)
        }
        error = nil
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
