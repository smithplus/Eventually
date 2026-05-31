import Foundation

@MainActor
class GoogleTasksService: ObservableObject {
    @Published var taskLists: [TaskList] = []
    @Published var tasks: [String: [Task]] = [:]  // listId -> tasks
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
            var response = try JSONDecoder().decode(TasksResponse.self, from: data)
            var items = response.items ?? []
            items = items.map {
                var t = $0
                t.listId = listId
                return t
            }
            tasks[listId] = items
        } catch {
            self.error = error.localizedDescription
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
            var newTask = try JSONDecoder().decode(Task.self, from: data)
            newTask.listId = listId
            tasks[listId, default: []].insert(newTask, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func completeTask(_ task: Task) async {
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

    func deleteTask(_ task: Task) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        do {
            try await delete("/lists/\(listId)/tasks/\(task.id)", token: token)
            tasks[listId]?.removeAll { $0.id == task.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateTask(_ task: Task, title: String, notes: String?) async {
        guard let listId = task.listId,
              let token = await authService?.validAccessToken() else { return }

        var body: [String: Any] = ["title": title]
        body["notes"] = notes ?? ""

        do {
            let data = try await patch("/lists/\(listId)/tasks/\(task.id)", body: body, token: token)
            var updated = try JSONDecoder().decode(Task.self, from: data)
            updated.listId = listId
            if let idx = tasks[listId]?.firstIndex(where: { $0.id == task.id }) {
                tasks[listId]?[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Computed

    var allTasks: [Task] {
        tasks.values.flatMap { $0 }
    }

    var todayTasks: [Task] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return allTasks.filter { task in
            guard let due = task.due else { return false }
            return due >= today && due < tomorrow
        }
    }

    var overdueTasks: [Task] {
        let today = Calendar.current.startOfDay(for: Date())
        return allTasks.filter { task in
            guard let due = task.due else { return false }
            return due < today
        }
    }

    // MARK: - HTTP Helpers

    private func get(_ path: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func post(_ path: String, body: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func patch(_ path: String, body: [String: Any], token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    @discardableResult
    private func delete(_ path: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
