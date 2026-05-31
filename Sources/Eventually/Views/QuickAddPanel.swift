import SwiftUI

/// Floating quick-add panel (KiteTasks-style).
/// Opened via ⌘⇧O, separate from the menu bar popover.
struct QuickAddPanel: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    @EnvironmentObject var authService: AuthService

    /// Called to dismiss the hosting window.
    var onClose: () -> Void

    @State private var nameText = ""
    @State private var selectedListId: String?
    @State private var manualDueDate: Date?
    @State private var showDatePicker = false

    /// Which tasks are shown below the input.
    @State private var panelFilter: GoogleTasksService.Selection = .all

    @FocusState private var nameFocused: Bool

    private var panelFilterListId: String? {
        if case .list(let id) = panelFilter { return id }
        return nil
    }

    private var displayRows: [GoogleTasksService.OrderedTask] {
        tasksService.rows(for: panelFilter)
    }

    // Live parse of whatever is in the name field
    private var parsed: QuickAddParser.Result {
        QuickAddParser.parse(nameText)
    }

    /// The list resolved from a `#token`, if it matches a real list.
    private var resolvedList: TaskList? {
        guard let name = parsed.listName?.lowercased() else { return nil }
        return tasksService.taskLists.first { $0.title.lowercased().hasPrefix(name) }
    }

    private var effectiveListId: String? {
        selectedListId ?? resolvedList?.id ?? panelFilterListId ?? tasksService.taskLists.first?.id
    }

    // MARK: - #list autocomplete

    /// The partial list name being typed: the last word, if it starts with `#`
    /// and isn't yet completed with a trailing space.
    private var hashFragment: String? {
        guard !nameText.hasSuffix(" "),
              let last = nameText.split(separator: " ").last,
              last.hasPrefix("#") else { return nil }
        return String(last.dropFirst())
    }

    /// Lists matching the current `#fragment` (substring match, like KiteTasks).
    private var listSuggestions: [TaskList] {
        guard let frag = hashFragment else { return [] }
        if frag.isEmpty { return tasksService.taskLists }
        return tasksService.taskLists.filter {
            $0.title.localizedCaseInsensitiveContains(frag)
        }
    }

    private var showListSuggestions: Bool {
        nameFocused && !listSuggestions.isEmpty
    }

    private var effectiveDueDate: Date? {
        manualDueDate ?? parsed.dueDate
    }

    private var canSubmit: Bool {
        !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: quick-add input
            VStack(alignment: .leading, spacing: Theme.spaceS) {
                nameField
                if showListSuggestions {
                    listSuggestionsDropdown
                } else {
                    headerControls
                }
            }
            .padding(Theme.spaceL)

            Divider()
            filterTabs
            Divider()
            taskListSection
        }
        .frame(width: 540)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { nameFocused = true }
        .onExitCommand { onClose() }
        .task { await tasksService.fetchTaskLists() }
    }

    // MARK: - Header controls (date chips + add)

    private var headerControls: some View {
        HStack(spacing: Theme.spaceS) {
            quickDateChip("Today", date: Calendar.current.startOfDay(for: Date()))
            quickDateChip("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))

            Button { showDatePicker.toggle() } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .padding(.horizontal, Theme.spaceS + 2)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .background(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .popover(isPresented: $showDatePicker) {
                DatePicker("Due date", selection: Binding(
                    get: { manualDueDate ?? Date() },
                    set: { manualDueDate = Calendar.current.startOfDay(for: $0) }
                ), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            }

            if let due = effectiveDueDate {
                parsedChip(text: dueLabel(due), system: "calendar", color: Theme.dateChip, soft: Theme.dateChipSoft)
            }

            Spacer()

            Button { submit() } label: {
                Text("Add").fontWeight(.semibold).padding(.horizontal, Theme.spaceXS)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Theme.accent)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - Filter tabs (All + lists)

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.spaceXS) {
                filterTab("All", isSelected: panelFilter == .all) { panelFilter = .all }
                ForEach(tasksService.taskLists) { list in
                    filterTab(list.title, isSelected: panelFilter == .list(list.id)) {
                        panelFilter = .list(list.id)
                    }
                }
            }
            .padding(.horizontal, Theme.spaceM)
            .padding(.vertical, Theme.spaceS)
        }
    }

    private func filterTab(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.accent : .secondary)
                .padding(.horizontal, Theme.spaceM)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Theme.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Task list

    @ViewBuilder
    private var taskListSection: some View {
        if displayRows.isEmpty {
            VStack(spacing: Theme.spaceS) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("No tasks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayRows) { ordered in
                        TaskRowView(task: ordered.task, isChild: ordered.isChild, showListBadge: panelFilter == .all)
                        Divider().padding(.leading, ordered.isChild ? 64 : 40)
                    }
                }
                .padding(.bottom, Theme.spaceS)
            }
            .frame(height: 360)
        }
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("", text: $nameText, prompt: Text("Task name  ·  use # for list"))
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .medium))
            .focused($nameFocused)
            .onSubmit {
                // Enter accepts the top autocomplete suggestion, else adds the task
                if showListSuggestions, let first = listSuggestions.first {
                    selectList(first)
                } else {
                    submit()
                }
            }
    }

    // MARK: - #list autocomplete dropdown

    private var listSuggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(listSuggestions.prefix(5).enumerated()), id: \.element.id) { index, list in
                Button {
                    selectList(list)
                } label: {
                    HStack(spacing: Theme.spaceS) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(list.title)
                            .font(.system(size: 14))
                        Spacer()
                    }
                    .padding(.horizontal, Theme.spaceM)
                    .padding(.vertical, Theme.spaceS + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(index == 0 ? Theme.accentSoft : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .padding(.top, Theme.spaceS)
    }

    /// Replace the `#fragment` token with the chosen list and pin the selection.
    private func selectList(_ list: TaskList) {
        var tokens = nameText.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !tokens.isEmpty {
            // Collapse spaces so the title stays a single #token
            tokens[tokens.count - 1] = "#" + list.title.replacingOccurrences(of: " ", with: "")
        }
        nameText = tokens.joined(separator: " ") + " "
        selectedListId = list.id
        nameFocused = true
    }

    private func quickDateChip(_ label: String, date: Date?) -> some View {
        let isSelected = manualDueDate != nil && date != nil && Calendar.current.isDate(manualDueDate!, inSameDayAs: date!)
        return Button {
            manualDueDate = date
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, Theme.spaceM)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Theme.dateChip : .secondary)
        .background(
            Capsule().fill(isSelected ? Theme.dateChipSoft : Color.clear)
        )
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.15), lineWidth: 1)
        )
    }

    private func parsedChip(text: String, system: String, color: Color, soft: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 11))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.spaceS + 2)
        .padding(.vertical, 5)
        .background(Capsule().fill(soft))
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit, let listId = effectiveListId else { return }
        let title = parsed.title
        let due = effectiveDueDate

        Task {
            await tasksService.addTask(title: title, due: due, to: listId)
        }

        // Keep the panel open so the user can keep adding / reviewing.
        nameText = ""
        manualDueDate = nil
        selectedListId = nil
        nameFocused = true
    }

    private func dueLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        f.dateFormat = abs(days) < 7 ? "EEEE" : "MMM d"
        return f.string(from: date)
    }
}
