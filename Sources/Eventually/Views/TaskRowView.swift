import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    let task: GTask
    var isChild: Bool = false
    var showListBadge: Bool = false
    var showDateBadge: Bool = true
    /// Parent tracks which task is expanded by ID — guarantees mutual exclusion
    @Binding var expandedTaskID: String?

    private var isExpanded: Bool { expandedTaskID == task.id }

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
                Spacer(minLength: 0)
                // Hover actions OR expand chevron
                if isHovering && !isExpanded {
                    hoverActions
                } else if isHovering && isExpanded {
                    // nothing — expanded state has Done button inline
                }
            }

            if showSubtaskInput {
                subtaskInputRow
            }
        }
        .padding(.horizontal, Theme.spaceM + 2)
        .padding(.vertical, isChild ? 8 : 10)
        // #7 — defined surface on hover instead of opacity hack
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isExpanded ? Color.primary.opacity(0.06) :
                      isHovering ? Color.primary.opacity(0.04) : .clear)
        )
        // Tap anywhere on the row (except checkbox/buttons) to expand.
        // .contentShape ensures the full padded area is hittable.
        .contentShape(Rectangle())
        .onTapGesture { if !isExpanded { expand() } }
        .onHover { isHovering = $0 }
        .contextMenu { taskMenuItems }
        .popover(isPresented: $showDatePicker) {
            // Auto-commits on day selection (consistent with quick-add date picker)
            DatePicker("", selection: Binding(
                get: { pickerDate },
                set: { newDate in
                    pickerDate = newDate
                    Task { await tasksService.setDueDate(task, to: newDate) }
                    showDatePicker = false
                }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(8)
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
        VStack(alignment: .leading, spacing: 5) {
            // #3 — tight letter-spacing like Linear body text
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 13.5, weight: .medium))
                .tracking(-0.2)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(2)

            // Notes preview — plain Text so it doesn't intercept row tap gestures.
            if let notes = task.notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    Text(notes)
                        .font(.system(size: 11))
                        .tracking(-0.1)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // #4 — metadata hierarchy: date (colored badge) > list (dot+text) > recurrence (icon only)
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
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title
            TextField("Title", text: $editTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .focused($isEditFocused)
                .onSubmit { saveDetail() }

            // Notes — inline, no background, no toolbar. Click rendered text to edit.
            if editingNotes {
                TextEditor(text: $editNotes)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 48, maxHeight: 220)
                    .focused($isNotesFocused)
                    .padding(.leading, -4) // align with title
            } else if editNotes.isEmpty {
                Text("Add notes…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .onTapGesture { startEditingNotes() }
            } else {
                MarkdownView(text: editNotes)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .contentShape(Rectangle())
                    .onTapGesture { startEditingNotes() }
            }

            // Bottom bar: date + Done
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

                doneButton
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func dueButtonLabel(_ date: Date) -> String {
        formatDueDate(date)
    }

    // #1 — date badge: 4px radius (not capsule), colored by urgency — highest priority metadata
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
                .tracking(-0.1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    // #4 — list badge: dot + text only, no background — secondary metadata, doesn't need a pill
    private func listBadge(_ listId: String) -> some View {
        let color = tasksService.listColor(for: listId)
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(tasksService.listTitle(for: listId) ?? "")
                .font(.system(size: 11))
                .tracking(-0.1)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // #4 — recurrence badge: icon + text, no background — tertiary metadata, quietest level
    private var recurrenceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9))
            if let pattern = task.recurrencePattern {
                Text(pattern.rawValue)
                    .font(.system(size: 11))
                    .tracking(-0.1)
            }
        }
        .foregroundStyle(.quaternary)
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

    /// Done button — shows ⌘↵ hint and only registers the shortcut when expanded.
    @ViewBuilder
    private var doneButton: some View {
        let btn = Button(action: saveDetail) {
            HStack(spacing: 5) {
                Text("Done")
                Text("⌘↵")
                    .font(.system(size: 10))
                    .opacity(0.7)
            }
        }
        .buttonStyle(CapsuleButton())
        if isExpanded {
            btn.keyboardShortcut(.return, modifiers: .command)
        } else {
            btn
        }
    }

    // MARK: - Markdown format helpers

    /// Wraps the selected text (or inserts markers at cursor) with a markdown wrapper like **bold**.
    private func formatButton(_ label: String, help: String, wrap: String) -> some View {
        Button {
            editNotes = applyWrap(wrap, to: editNotes)
        } label: {
            Text(label == "I" ? "_\(label)_" : label)
                .font(.system(size: 11, weight: label == "B" ? .bold : .regular))
                .italic(label == "I")
                .frame(width: 22, height: 18)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func formatPrefixButton(_ label: String, help: String, prefix: String) -> some View {
        Button {
            // Prepend prefix to the last line
            let lines = editNotes.components(separatedBy: "\n")
            if var last = lines.last, !last.hasPrefix(prefix) {
                last = prefix + last
                editNotes = (lines.dropLast() + [last]).joined(separator: "\n")
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 18)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func applyWrap(_ wrap: String, to text: String) -> String {
        // If text already ends with the closing marker, we're toggling off — strip both markers.
        // We check for the single marker (e.g. "**"), not doubled, because real content sits between them.
        if text.hasSuffix(wrap) && text.contains(wrap) {
            // Remove the trailing marker and the leading marker from the last occurrence
            if let range = text.range(of: wrap, options: .backwards) {
                let withoutTrailing = String(text[..<range.lowerBound])
                if let leadingRange = withoutTrailing.range(of: wrap, options: .backwards) {
                    return String(withoutTrailing[..<leadingRange.lowerBound]) + String(withoutTrailing[leadingRange.upperBound...])
                }
            }
        }
        // Append opening + closing markers (cursor lands between them)
        return text + wrap + wrap
    }

    private func expand() {
        editTitle = task.title
        editNotes = task.notes ?? ""
        editingNotes = false   // show rendered markdown first; tap to edit
        withAnimation(.easeOut(duration: 0.15)) {
            expandedTaskID = task.id  // sets isExpanded = true via computed prop
        }
        // Delay focus until after the expand animation inserts the TextField
        DispatchQueue.main.async { isEditFocused = true }
    }

    private func startEditingNotes() {
        editingNotes = true
        isNotesFocused = true
    }

    private func saveDetail() {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.easeOut(duration: 0.15)) {
            expandedTaskID = nil  // sets isExpanded = false via computed prop
        }

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
