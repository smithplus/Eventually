import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    let task: GTask
    var isChild: Bool = false
    var showListBadge: Bool = false
    var showDateBadge: Bool = true

    @State private var isExpanded = false
    @State private var editTitle = ""
    @State private var editNotes = ""
    @State private var editingNotes = false
    @FocusState private var isEditFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @State private var isHovering = false

    @State private var showDatePicker = false
    @State private var pickerDate = Date()
    @State private var showSubtaskInput = false
    @State private var subtaskTitle = ""
    @FocusState private var isSubtaskFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if isChild {
                    // Subtask indent guide
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 2, height: 18)
                        .padding(.leading, Theme.spaceM)
                        .padding(.trailing, 4)
                }
                checkboxButton
                taskContent
                if !isExpanded { Spacer(minLength: 0) }
                if isHovering && !isExpanded {
                    hoverActions
                }
            }

            if showSubtaskInput {
                subtaskInputRow
            }
        }
        .padding(.horizontal, Theme.spaceM + 2)
        .padding(.vertical, isChild ? 8 : 10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill((isHovering || isExpanded) ? Color.primary.opacity(0.05) : .clear)
        )
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
            Task {
                if task.isCompleted {
                    await tasksService.uncompleteTask(task)
                } else {
                    await tasksService.completeTask(task)
                }
            }
        } label: {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(task.isCompleted ? .green : .secondary)
                .scaleEffect(task.isCompleted ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: task.isCompleted)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 13.5, weight: .medium))
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(2)

            if let notes = task.notes, !notes.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                    Text(markdown(notes))
                        .lineLimit(isExpanded ? 8 : 1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }

            // Metadata row: due date + list badge + recurrence
            if (showDateBadge && task.dueDay != nil) || (showListBadge && task.listId != nil) || task.isRecurring {
                HStack(spacing: 6) {
                    if showDateBadge, let due = task.dueDay {
                        dueBadge(due)
                    }
                    if showListBadge, let listId = task.listId {
                        listBadge(listId)
                    }
                    if task.isRecurring {
                        recurrenceBadge
                    }
                }
                .padding(.top, 2)
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

            // Description / notes — rendered markdown by default; tap to edit the source.
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                if editingNotes {
                    TextEditor(text: $editNotes)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 36, maxHeight: 180)
                        .focused($isNotesFocused)
                } else if editNotes.isEmpty {
                    Text("Add description · markdown")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 3)
                        .onTapGesture { startEditingNotes() }
                } else {
                    MarkdownView(text: editNotes)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { startEditingNotes() }
                }
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
                .tint(task.due != nil ? Theme.dateChip : .secondary)

                if showListBadge, let listId = task.listId {
                    listBadge(listId)
                }

                Spacer()

                Button("Done") { saveDetail() }
                    .buttonStyle(CapsuleButton())
                    .keyboardShortcut(.return, modifiers: .command)
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
        let color: Color = isOverdue ? Theme.danger : isToday ? Theme.dateChip : .secondary
        let bgColor: Color = isOverdue ? Theme.danger.opacity(0.12) : isToday ? Theme.dateChip.opacity(0.12) : Color.primary.opacity(0.06)

        return HStack(spacing: 4) {
            Image(systemName: isOverdue ? "exclamationmark.circle.fill" : "calendar")
                .font(.system(size: 9))
            Text(formatDueDate(date))
                .font(.system(size: 11, weight: isOverdue || isToday ? .medium : .regular))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bgColor)
        .clipShape(Capsule())
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private var recurrenceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9))
            if let pattern = task.recurrencePattern {
                Text(pattern.rawValue)
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
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
        editingNotes = false   // show rendered markdown first; tap to edit
        withAnimation(.easeOut(duration: 0.15)) { isExpanded = true }
        isEditFocused = true
    }

    private func startEditingNotes() {
        editingNotes = true
        isNotesFocused = true
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

    /// Render note text as markdown (bold, italic, links, line breaks).
    private func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
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
