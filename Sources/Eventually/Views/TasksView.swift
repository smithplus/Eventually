import SwiftUI

struct TasksView: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    @EnvironmentObject var authService: AuthService

    @State private var selectedListId: String?
    @State private var showAddTask = false
    @State private var addTaskFocused = false
    @State private var newTaskTitle = ""
    @FocusState private var isInputFocused: Bool

    var currentListId: String? {
        selectedListId ?? tasksService.taskLists.first?.id
    }

    var currentTasks: [Task] {
        guard let listId = currentListId else { return [] }
        return tasksService.tasks[listId] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            addTaskRow
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

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(.blue)
                .font(.system(size: 14, weight: .semibold))

            if tasksService.taskLists.isEmpty {
                Text("My Tasks")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Menu {
                    ForEach(tasksService.taskLists) { list in
                        Button(list.title) {
                            selectedListId = list.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tasksService.taskLists.first(where: { $0.id == currentListId })?.title ?? "My Tasks")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

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

    private var settingsMenu: some View {
        Menu {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            Button("Sign Out") {
                authService.signOut()
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
                    ForEach(currentTasks) { task in
                        TaskRowView(task: task)
                        Divider().padding(.leading, 40)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 420)
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
        .frame(height: 120)
    }

    // MARK: - Actions

    private func submitNewTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let listId = currentListId else { return }
        newTaskTitle = ""
        showAddTask = false
        Task {
            await tasksService.addTask(title: title, to: listId)
        }
    }
}
