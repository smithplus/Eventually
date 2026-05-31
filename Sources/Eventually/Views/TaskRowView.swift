import SwiftUI

struct TaskRowView: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    let task: Task

    @State private var isEditing = false
    @State private var editTitle = ""
    @FocusState private var isEditFocused: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            checkboxButton
            taskContent
            Spacer()
            if isHovering && !isEditing {
                deleteButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
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
        if isEditing {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Task title", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isEditFocused)
                    .onSubmit { saveEdit() }
                    .onExitCommand { cancelEdit() }

                HStack(spacing: 8) {
                    Button("Save") { saveEdit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Cancel") { cancelEdit() }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                    .onTapGesture(count: 2) { startEditing() }

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let due = task.due {
                    dueBadge(due)
                }
            }
        }
    }

    private func dueBadge(_ date: Date) -> some View {
        let isOverdue = date < Calendar.current.startOfDay(for: Date())
        let isToday = Calendar.current.isDateInToday(date)

        return HStack(spacing: 3) {
            Image(systemName: "calendar")
                .font(.system(size: 9))
            Text(formatDueDate(date))
                .font(.system(size: 11))
        }
        .foregroundStyle(isOverdue ? .red : isToday ? .orange : .secondary)
    }

    private var deleteButton: some View {
        Button {
            Task { await tasksService.deleteTask(task) }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func startEditing() {
        editTitle = task.title
        isEditing = true
        isEditFocused = true
    }

    private func saveEdit() {
        let title = editTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { cancelEdit(); return }
        isEditing = false
        Task {
            await tasksService.updateTask(task, title: title, notes: task.notes)
        }
    }

    private func cancelEdit() {
        isEditing = false
        editTitle = ""
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
