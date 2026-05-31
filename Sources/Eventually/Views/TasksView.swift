import SwiftUI

struct TasksView: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    @EnvironmentObject var authService: AuthService

    @State private var selection: GoogleTasksService.Selection = .today
    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @FocusState private var isInputFocused: Bool

    /// The list a new task should be added to (smart views fall back to first list).
    var targetListId: String? {
        if case .list(let id) = selection { return id }
        return tasksService.taskLists.first?.id
    }

    /// Whether the current view aggregates multiple lists (→ show list badges).
    var isSmartView: Bool {
        if case .list = selection { return false }
        return true
    }

    var currentTasks: [GoogleTasksService.OrderedTask] {
        tasksService.rows(for: selection)
    }

    private var selectionTitle: String {
        switch selection {
        case .all:      return "All Tasks"
        case .today:    return "Today"
        case .upcoming: return "Upcoming"
        case .list(let id): return tasksService.listTitle(for: id) ?? "My Tasks"
        }
    }

    private var selectionIcon: String {
        switch selection {
        case .all:      return "tray.full"
        case .today:    return "sun.max"
        case .upcoming: return "calendar"
        case .list:     return "list.bullet"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            addTaskRow
            if let error = tasksService.error {
                errorBanner(error)
            }
            Divider()
            taskContent
        }
        .task {
            await tasksService.fetchTaskLists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddTask)) { _ in
            showAddTask = true
            isInputFocused = true
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.08))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: selectionIcon)
                .foregroundStyle(Theme.accent)
                .font(.system(size: 14, weight: .semibold))

            Menu {
                Button { selection = .today } label: { Label("Today", systemImage: "sun.max") }
                Button { selection = .upcoming } label: { Label("Upcoming", systemImage: "calendar") }
                Button { selection = .all } label: { Label("All Tasks", systemImage: "tray.full") }
                if !tasksService.taskLists.isEmpty {
                    Divider()
                    ForEach(tasksService.taskLists) { list in
                        Button { selection = .list(list.id) } label: { Text(list.title) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectionTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            sortMenu

            if tasksService.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    Task { await tasksService.fetchTaskLists() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            settingsMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: Binding(
                get: { tasksService.sortOrder },
                set: { tasksService.sortOrder = $0 }
            )) {
                ForEach(GoogleTasksService.SortOrder.allCases, id: \.self) { order in
                    Label(order.label, systemImage: order.icon).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var settingsMenu: some View {
        Menu {
            if let email = authService.userEmail {
                Section(email) {
                    Button("Settings...") { openSettings() }
                    Button("Sign Out") { authService.signOut() }
                }
            } else {
                Button("Settings...") { openSettings() }
            }
            Divider()
            Button("Quit Eventually") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Opens the Settings window (selector differs between macOS 13 and 14+).
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Add Task Row

    private var addTaskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 16))
                .onTapGesture {
                    showAddTask = true
                    isInputFocused = true
                }

            if showAddTask {
                TextField("Add a task", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isInputFocused)
                    .onSubmit { submitNewTask() }
                    .onExitCommand {
                        showAddTask = false
                        newTaskTitle = ""
                    }

                if !newTaskTitle.isEmpty {
                    Button("Add") { submitNewTask() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Text("Add a task")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        showAddTask = true
                        isInputFocused = true
                    }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.background)
        .contentShape(Rectangle())
        .onTapGesture {
            if !showAddTask {
                showAddTask = true
                isInputFocused = true
            }
        }
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskContent: some View {
        if currentTasks.isEmpty && !tasksService.isLoading {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(currentTasks) { ordered in
                        TaskRowView(task: ordered.task, isChild: ordered.isChild, showListBadge: isSmartView)
                        Divider().padding(.leading, ordered.isChild ? 64 : 40)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(minHeight: 200, maxHeight: 560)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    // MARK: - Actions

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let listId = targetListId else { return }
        newTaskTitle = ""
        showAddTask = false
        Task {
            await tasksService.addTask(title: title, to: listId)
        }
    }
}
