import SwiftUI

/// Floating quick-add panel (KiteTasks-style).
/// Opened via ⌘⇧O, separate from the menu bar popover.
struct QuickAddPanel: View {
    @EnvironmentObject var tasksService: GoogleTasksService
    @EnvironmentObject var authService: AuthService

    /// Called to dismiss the hosting window.
    var onClose: () -> Void

    @EnvironmentObject private var draft: QuickAddDraft
    @State private var showDatePicker = false

    @State private var searchText = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    /// Which tasks are shown below the input.
    @State private var panelFilter: GoogleTasksService.Selection = .today

    @AppStorage("defaultCommandView") private var defaultCommandView = "today"

    @FocusState private var nameFocused: Bool

    private var panelFilterListId: String? {
        if case .list(let id) = panelFilter { return id }
        return nil
    }

    private var displayRows: [GoogleTasksService.OrderedTask] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if showSearch && !q.isEmpty {
            return tasksService.search(q)
        }
        return tasksService.rows(for: panelFilter)
    }

    // MARK: - Default / last-used view

    private func defaultSelection() -> GoogleTasksService.Selection {
        let key = defaultCommandView == "lastUsed"
            ? (UserDefaults.standard.string(forKey: DefaultsKey.lastCommandView) ?? "today")
            : defaultCommandView
        return GoogleTasksService.Selection(storageKey: key, lists: tasksService.taskLists)
    }

    private func saveLastUsed(_ sel: GoogleTasksService.Selection) {
        UserDefaults.standard.set(sel.storageKey, forKey: DefaultsKey.lastCommandView)
    }

    // Live parse of whatever is in the name field
    private var parsed: QuickAddParser.Result {
        QuickAddParser.parse(draft.name)
    }

    /// The list resolved from a `#token`, if it matches a real list.
    private var resolvedList: TaskList? {
        guard let name = parsed.listName?.lowercased() else { return nil }
        return tasksService.taskLists.first { $0.title.lowercased().hasPrefix(name) }
    }

    private var effectiveListId: String? {
        draft.listId ?? resolvedList?.id ?? panelFilterListId ?? tasksService.taskLists.first?.id
    }

    // MARK: - #list autocomplete

    /// The partial list name being typed: the last word, if it starts with `#`
    /// and isn't yet completed with a trailing space.
    private var hashFragment: String? {
        guard !draft.name.hasSuffix(" "),
              let last = draft.name.split(separator: " ").last,
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
        draft.dueDate ?? parsed.dueDate
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
                if let error = tasksService.error {
                    errorBanner(error)
                }
            }
            .padding(Theme.spaceL)

            Divider()
            filterToolbar
            Divider()
            taskListSection
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            nameFocused = true
            panelFilter = defaultSelection()
        }
        .onChange(of: panelFilter) { saveLastUsed($0) }
        .onExitCommand { handleEscape() }
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
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                datePickerPopover
            }

            if let due = effectiveDueDate {
                parsedChip(text: dueLabel(due), system: "calendar", color: Theme.dateChip, soft: Theme.dateChipSoft)
            }

            Spacer()

            Button("Add task") { submit() }
                .buttonStyle(CapsuleButton(enabled: canSubmit))
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: - Date picker popover

    private var datePickerPopover: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            DatePicker("", selection: Binding(
                get: { draft.dueDate ?? Date() },
                set: { draft.dueDate = Calendar.current.startOfDay(for: $0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Theme.accent)

            Divider()

            HStack {
                if draft.dueDate != nil {
                    Button("Clear") { draft.dueDate = nil; showDatePicker = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.danger)
                }
                Spacer()
                Button("Done") { showDatePicker = false }
                    .buttonStyle(CapsuleButton())
            }
        }
        .padding(Theme.spaceM)
        .frame(width: 280)
    }

    // MARK: - Filter toolbar (smart views + lists, with controls on the right)

    @ViewBuilder
    private var filterToolbar: some View {
        if showSearch {
            searchBar
        } else {
            HStack(spacing: Theme.spaceS) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spaceXS) {
                        filterTab("Today", icon: "sun.max", isSelected: panelFilter == .today) { panelFilter = .today }
                        filterTab("Upcoming", icon: "calendar", isSelected: panelFilter == .upcoming) { panelFilter = .upcoming }
                        filterTab("All", icon: "tray.full", isSelected: panelFilter == .all) { panelFilter = .all }
                        ForEach(tasksService.taskLists) { list in
                            filterTab(list.title, icon: nil, isSelected: panelFilter == .list(list.id)) {
                                panelFilter = .list(list.id)
                            }
                        }
                    }
                    .padding(.leading, Theme.spaceM)
                }

                controlsCluster
                    .padding(.trailing, Theme.spaceM)
            }
            .padding(.vertical, Theme.spaceS)
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.spaceS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            Button {
                closeSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.spaceM)
        .padding(.vertical, Theme.spaceS)
    }

    private func openSearch() {
        showSearch = true
        searchFocused = true
    }

    private func closeSearch() {
        showSearch = false
        searchText = ""
    }

    private func filterTab(_ title: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 10)) }
                Text(title)
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Theme.accent : .secondary)
            .padding(.horizontal, Theme.spaceM)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? Theme.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Controls (sort + refresh + ⋯), parity with the popover

    private var controlsCluster: some View {
        HStack(spacing: Theme.spaceS) {
            Button { openSearch() } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)

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
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)

            if tasksService.isLoading {
                ProgressView().controlSize(.mini)
            } else {
                Button { Task { await tasksService.fetchTaskLists() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }

            Menu {
                if let email = authService.userEmail {
                    Section(email) {
                        Button("Settings...") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                        Button("Sign Out") { authService.signOut() }
                    }
                } else {
                    Button("Settings...") { NotificationCenter.default.post(name: .openSettings, object: nil) }
                }
                Divider()
                Button("Quit Eventually") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger).font(.system(size: 11))
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.top, Theme.spaceXS)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayRows) { ordered in
                        TaskRowView(task: ordered.task, isChild: ordered.isChild, showListBadge: panelFilter.isSmart || showSearch)
                        Divider().padding(.leading, ordered.isChild ? 64 : 40)
                    }
                }
                .padding(.bottom, Theme.spaceS)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("", text: $draft.name, prompt: Text("Task name  ·  use # for list"))
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
        var tokens = draft.name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !tokens.isEmpty {
            // Collapse spaces so the title stays a single #token
            tokens[tokens.count - 1] = "#" + list.title.replacingOccurrences(of: " ", with: "")
        }
        draft.name = tokens.joined(separator: " ") + " "
        draft.listId = list.id
        nameFocused = true
    }

    private func quickDateChip(_ label: String, date: Date?) -> some View {
        let isSelected = draft.dueDate != nil && date != nil && Calendar.current.isDate(draft.dueDate!, inSameDayAs: date!)
        return Button {
            draft.dueDate = date
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
        draft.clear()
        nameFocused = true
    }

    /// Esc closes search first, then clears the draft, then closes — Raycast-style.
    private func handleEscape() {
        if showSearch {
            closeSearch()
        } else if !draft.isEmpty {
            draft.clear()
        } else {
            onClose()
        }
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
