import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    let task: GTask
    var isChild: Bool = false
    var showListBadge: Bool = false

    @State private var isExpanded = false
    @State private var editTitle = ""
    @State private var editNotes = ""
    @FocusState private var isEditFocused: Bool
    @State private var isHovering = false

    @State private var showDatePicker = false
    @State private var pickerDate = Date()
    @State private var showSubtaskInput = false
    @State private var subtaskTitle = ""
    @FocusState private var isSubtaskFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                if isChild {
                    // Subtask indent guide
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1.5, height: 16)
                        .padding(.leading, 14)
                        .padding(.trailing, 2)
                }
                checkboxButton
                taskContent
                if !isExpanded { Spacer() }
                if isHovering && !isExpanded {
                    hoverActions
                }
            }

            if showSubtaskInput {
                subtaskInputRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isChild ? 6 : 8)
        .background((isHovering || isExpanded) ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
        .contextMenu { taskMenuItems }
        .popover(isPresented: $showDatePicker) {
            VStack(spacing: 8) {
                DatePicker("Due date", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                Button("Save") {
                    Task { await tasksService.setDueDate(task, to: pickerDate) }
                    showDatePicker = false
                }
                .buttonStyle(CapsuleButton())
            }
            .padding()
        }
    }

    // MARK: - Per-task options menu

    @ViewBuilder
    private var taskMenuItems: some View {
        Button { openDatePicker() } label: { Label("Edit due date", systemImage: "calendar") }
        if task.due != nil {
            Button { Task { await tasksService.setDueDate(task, to: nil) } } label: {
                Label("Clear due date", systemImage: "calendar.badge.minus")
            }
        }
        if !isChild {
            Button { startSubtask() } label: { Label("Add subtask", systemImage: "arrow.turn.down.right") }
        }
        if tasksService.taskLists.count > 1 {
            Menu {
                ForEach(tasksService.taskLists.filter { $0.id != task.listId }) { list in
                    Button(list.title) { Task { await tasksService.moveTask(task, toList: list.id) } }
                }
            } label: { Label("Move to list", systemImage: "tray.and.arrow.up") }
        }
        Divider()
        Button(role: .destructive) { Task { await tasksService.deleteTask(task) } } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var optionsMenu: some View {
        Menu {
            taskMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Quick-action icons shown on hover: due date, add subtask, more.
    private var hoverActions: some View {
        HStack(spacing: 2) {
            iconButton("calendar", help: "Edit due date") { openDatePicker() }
            if !isChild {
                iconButton("arrow.turn.down.right", help: "Add subtask") { startSubtask() }
            }
            optionsMenu
        }
    }

    private func iconButton(_ system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var subtaskInputRow: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1.5, height: 16)
                .padding(.leading, 14)
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Subtask", text: $subtaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isSubtaskFocused)
                .onSubmit { commitSubtask() }
                .onExitCommand { cancelSubtask() }
                .deleteKeyOnEmpty(subtaskTitle.isEmpty) { cancelSubtask() }
        }
        .padding(.top, 6)
    }

    private var checkboxButton: some View {
        Button {
            Task { await tasksService.completeTask(task) }
        } label: {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(task.isCompleted ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
    }

    @ViewBuilder
    private var taskContent: some View {
        if isExpanded {
            expandedContent
        } else {
            collapsedContent
        }
    }

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 13))
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(2)

            if let notes = task.notes, !notes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                    Text(notes)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            // Metadata row: due date + list badge
            if task.dueDay != nil || (showListBadge && task.listId != nil) {
                HStack(spacing: 8) {
                    if let due = task.dueDay {
                        dueBadge(due)
                    }
                    if showListBadge, let listId = task.listId {
                        listBadge(listId)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { expand() }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $editTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .focused($isEditFocused)
                .onSubmit { saveDetail() }

            // Description / notes
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                TextField("Add description", text: $editNotes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1...6)
            }

            // Quick controls
            HStack(spacing: 8) {
                Button {
                    openDatePicker()
                } label: {
                    Label(task.due.map(dueButtonLabel) ?? "Due date",
                          systemImage: "calendar")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(task.due != nil ? Theme.accent : .secondary)

                if showListBadge, let listId = task.listId {
                    listBadge(listId)
                }

                Spacer()

                Button("Done") { saveDetail() }
                    .buttonStyle(CapsuleButton())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func dueButtonLabel(_ date: Date) -> String {
        formatDueDate(date)
    }

    private func dueBadge(_ date: Date) -> some View {
        let isOverdue = date < Calendar.current.startOfDay(for: Date()) && !task.isCompleted
        let isToday = Calendar.current.isDateInToday(date)
        let color: Color = isOverdue ? Theme.danger : isToday ? Theme.accent : .secondary

        return HStack(spacing: 3) {
            Image(systemName: isOverdue ? "exclamationmark.circle" : "calendar")
                .font(.system(size: 9))
            Text(formatDueDate(date))
                .font(.system(size: 11, weight: isOverdue || isToday ? .medium : .regular))
        }
        .foregroundStyle(color)
    }

    private func listBadge(_ listId: String) -> some View {
        let color = tasksService.listColor(for: listId)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(tasksService.listTitle(for: listId) ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func openDatePicker() {
        pickerDate = task.due ?? Date()
        showDatePicker = true
    }

    private func startSubtask() {
        subtaskTitle = ""
        showSubtaskInput = true
        isSubtaskFocused = true
    }

    private func commitSubtask() {
        let title = subtaskTitle.trimmingCharacters(in: .whitespaces)
        showSubtaskInput = false
        guard !title.isEmpty else { return }
        subtaskTitle = ""
        Task { await tasksService.addSubtask(to: task, title: title) }
    }

    private func cancelSubtask() {
        showSubtaskInput = false
        subtaskTitle = ""
    }

    private func expand() {
        editTitle = task.title
        editNotes = task.notes ?? ""
        withAnimation(.easeOut(duration: 0.15)) { isExpanded = true }
        isEditFocused = true
    }

    private func saveDetail() {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.easeOut(duration: 0.15)) { isExpanded = false }

        let titleChanged = title != task.title && !title.isEmpty
        let notesChanged = notes != (task.notes ?? "")
        guard titleChanged || notesChanged else { return }

        Task {
            await tasksService.updateTask(
                task,
                title: title.isEmpty ? task.title : title,
                notes: notes.isEmpty ? nil : notes
            )
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        let daysAway = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if abs(daysAway) < 7 {
            formatter.dateFormat = "EEEE"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}

// MARK: - Delete-on-empty helper

extension View {
    /// Calls `perform` when the Delete (backspace) key is pressed while the
    /// field is empty — used to remove an empty new-subtask input.
    @ViewBuilder
    func deleteKeyOnEmpty(_ isEmpty: Bool, perform: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onKeyPress(.delete) {
                if isEmpty {
                    perform()
                    return .handled
                }
                return .ignored
            }
        } else {
            self
        }
    }
}
