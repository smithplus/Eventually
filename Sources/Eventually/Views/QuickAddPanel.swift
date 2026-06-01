import SwiftUI

/// Root of the Command Window: shows the login when signed out, the full
/// quick-add panel when signed in. The single UI surface of the app.
struct CommandRoot: View {
    @EnvironmentObject var authService: AuthService
    var onClose: () -> Void

    var body: some View {
        Group {
            if authService.isAuthenticated {
                QuickAddPanel(onClose: onClose)
            } else {
                LoginView()
                    .frame(minWidth: 540, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onExitCommand { onClose() }
            }
        }
    }
}

/// Floating quick-add panel (KiteTasks-style), opened via ⌘⇧O.
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

    @State private var renamingList: TaskList?
    @State private var renameText = ""
    @State private var showNewList = false
    @State private var newListText = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var suggestionIndex = 0
    @State private var completedCollapsed: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.completedSectionCollapsed)

    // Keyboard navigation of the task list + multi-select.
    @FocusState private var listFocused: Bool
    @State private var cursorIndex = 0
    @State private var selectedTaskIDs: Set<String> = []
    @State private var showBulkDatePicker = false
    @State private var bulkDate = Date()

    // Track when any task row is being edited (to prevent keyboard shortcuts from interfering)
    @State private var isAnyTaskBeingEdited = false

    /// The flat sequence of task rows currently visible (respects grouping and
    /// collapsed sections) — the order keyboard navigation walks.
    /// ONLY includes active (incomplete) tasks for navigation purposes.
    private var visibleRows: [GoogleTasksService.OrderedTask] {
        if isGroupedByDate {
            return tasksService.groupedByDate(activeTasks).flatMap {
                collapsedGroups.contains("date:" + $0.key) ? [] : $0.rows
            }
        } else if isGroupedByList {
            return tasksService.grouped(activeTasks).flatMap {
                collapsedGroups.contains($0.listId) ? [] : $0.rows
            }
        }
        return activeTasks
    }

    /// Tasks currently selected AND visible (selection is pruned on view change).
    private var selectedTasks: [GTask] {
        visibleRows.map(\.task).filter { selectedTaskIDs.contains($0.id) }
    }

    private var cursorTask: GTask? {
        visibleRows.indices.contains(cursorIndex) ? visibleRows[cursorIndex].task : nil
    }

    /// Which tasks are shown below the input.
    @State private var panelFilter: GoogleTasksService.Selection = .today

    @AppStorage("defaultCommandView") private var defaultCommandView = "today"
    @AppStorage(DefaultsKey.groupByList) private var groupByList = false
    @AppStorage(DefaultsKey.groupByDate) private var groupByDate = false

    @FocusState private var nameFocused: Bool
    @FocusState private var notesFocused: Bool

    /// Group the aggregated smart views into per-list sections.
    private var isGroupedByList: Bool {
        groupByList && panelFilter.isSmart && !showSearch
    }

    /// Group rows into date buckets (Overdue/Today/…); works in any view.
    private var isGroupedByDate: Bool {
        groupByDate && !showSearch
    }

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

    /// Active (incomplete) tasks from displayRows
    private var activeTasks: [GoogleTasksService.OrderedTask] {
        displayRows.filter { !$0.task.isCompleted }
    }

    /// Completed tasks from displayRows
    private var completedTasks: [GoogleTasksService.OrderedTask] {
        displayRows.filter { $0.task.isCompleted }
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
        guard let name = parsed.listName else { return nil }
        return matchList(name)
    }

    /// Match a list by name, ignoring spaces, so `#📋Lectura` matches "📋 Lectura".
    private func matchList(_ name: String) -> TaskList? {
        let needle = name.replacingOccurrences(of: " ", with: "").lowercased()
        guard !needle.isEmpty else { return nil }
        return tasksService.taskLists.first {
            $0.title.replacingOccurrences(of: " ", with: "").lowercased().contains(needle)
        }
    }

    /// A `#token` in the text is the most recent intent, so it wins over a
    /// previously-picked chip selection.
    private var effectiveListId: String? {
        resolvedList?.id ?? draft.listId ?? panelFilterListId ?? tasksService.taskLists.first?.id
    }

    /// True when the user typed a `#name` that matches no list AND hasn't picked
    /// one via the chip (so we don't warn when the list is actually set).
    private var unmatchedListToken: Bool {
        guard let name = parsed.listName, !name.isEmpty else { return false }
        return resolvedList == nil && draft.listId == nil
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

    // MARK: - !date autocomplete

    struct DateOption: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let date: Date?     // nil = "Custom…" (opens the picker)
    }

    /// Partial after the last `!`, if the last word starts with `!`.
    private var bangFragment: String? {
        guard !draft.name.hasSuffix(" "),
              let last = draft.name.split(separator: " ").last,
              last.hasPrefix("!") else { return nil }
        return String(last.dropFirst())
    }

    private var dateSuggestions: [DateOption] {
        guard let frag = bangFragment else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func add(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: today) ?? today }
        func next(_ weekday: Int) -> Date {
            var delta = weekday - cal.component(.weekday, from: today)
            if delta <= 0 { delta += 7 }
            return add(delta)
        }
        let all = [
            DateOption(label: "Today", icon: "sun.max", date: today),
            DateOption(label: "Tomorrow", icon: "sunrise", date: add(1)),
            DateOption(label: "This weekend", icon: "beach.umbrella", date: next(7)),
            DateOption(label: "Next week", icon: "calendar", date: next(2)),
            DateOption(label: "In 1 week", icon: "calendar.badge.clock", date: add(7)),
            DateOption(label: "Custom…", icon: "calendar.badge.plus", date: nil),
        ]
        if frag.isEmpty { return all }
        return all.filter { $0.label.localizedCaseInsensitiveContains(frag) }
    }

    private var showDateSuggestions: Bool {
        nameFocused && !dateSuggestions.isEmpty
    }

    private var anySuggestionsVisible: Bool { showListSuggestions || showDateSuggestions }

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
                } else if showDateSuggestions {
                    dateSuggestionsDropdown
                } else {
                    descriptionField
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
            if !selectedTasks.isEmpty {
                Divider()
                bulkActionBar
            }
        }
        .frame(minWidth: 540, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
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
        .onChange(of: panelFilter) { saveLastUsed($0); resetNavigation() }
        .onChange(of: searchText) { _ in resetNavigation() }
        .onChange(of: showSearch) { _ in resetNavigation() }
        .onChange(of: nameFocused) { focused in if focused { listFocused = false } }
        // Keep the cursor valid when the visible set shrinks (e.g. after a
        // complete/delete) so navigation never points past the end.
        .onChange(of: visibleRows.count) { count in
            cursorIndex = max(0, min(cursorIndex, count - 1))
        }
        .onExitCommand { if !listFocused { handleEscape() } }
        .task { await tasksService.fetchTaskLists() }
        .alert("Rename list", isPresented: Binding(
            get: { renamingList != nil },
            set: { if !$0 { renamingList = nil } }
        )) {
            TextField("List name", text: $renameText)
            Button("Rename") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if let list = renamingList, !t.isEmpty {
                    Task { await tasksService.renameList(list, to: t) }
                }
                renamingList = nil
            }
            Button("Cancel", role: .cancel) { renamingList = nil }
        }
        .alert("New list", isPresented: $showNewList) {
            TextField("List name", text: $newListText)
            Button("Create") {
                let t = newListText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { Task { await tasksService.createList(title: t) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Description (optional, markdown-friendly)

    private var descriptionField: some View {
        // Auto-grows with content (1...8 lines). Enter adds the task; Shift+Enter
        // inserts a newline (appended — works for linear typing).
        TextField("Description (optional · markdown)", text: $draft.notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1...8)
            .focused($notesFocused)
            .modifier(DescriptionKeyHandler(
                onEnter: { submit() },
                onShiftEnter: { draft.notes += "\n" }
            ))
    }

    // MARK: - Header controls (date chips + list selector + add)

    private var headerControls: some View {
        HStack(spacing: Theme.spaceS) {
            if let due = effectiveDueDate {
                // A date is set → show just it (tap to change, ✕ to clear).
                selectedDateChip(due)
            } else {
                quickDateChip("Today", date: Calendar.current.startOfDay(for: Date()))
                quickDateChip("Tomorrow", date: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
                Button { showDatePicker.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 11))
                        Text("Pick date").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.spaceM)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .background(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .popover(isPresented: $showDatePicker, arrowEdge: .bottom) { datePickerPopover }
                .fixedSize()
            }

            listSelectorChip

            Spacer()

            Button("Add task") { submit() }
                .buttonStyle(CapsuleButton(enabled: canSubmit))
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    /// The chosen due date as a chip: tap to re-pick, ✕ to clear.
    private func selectedDateChip(_ due: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar").font(.system(size: 11))
            Text(dueLabel(due)).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Button { clearDate() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.dateChip)
        .padding(.horizontal, Theme.spaceS + 2)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.dateChipSoft))
        .fixedSize()
        .onTapGesture { showDatePicker = true }
        .popover(isPresented: $showDatePicker, arrowEdge: .bottom) { datePickerPopover }
    }

    /// Clear the due date, including any `!token` typed in the title.
    private func clearDate() {
        draft.dueDate = nil
        var tokens = draft.name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        tokens.removeAll { $0.hasPrefix("!") }
        draft.name = tokens.joined(separator: " ")
    }

    /// List selector chip — pick the target list by click (alternative to `#`).
    private var listSelectorChip: some View {
        let warn = unmatchedListToken
        let color: Color = warn ? Theme.danger : tasksService.listColor(for: effectiveListId)
        return Menu {
            ForEach(tasksService.taskLists) { list in
                Button(list.title) { draft.listId = list.id }
            }
        } label: {
            HStack(spacing: 5) {
                if warn {
                    Image(systemName: "questionmark.circle").font(.system(size: 11))
                } else {
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                Text(warn ? "#\(parsed.listName!)?" : currentListName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.spaceM)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(color)
        .help(warn ? "No list named “\(parsed.listName!)” — pick one" : "Target list")
    }

    private var currentListName: String {
        if let id = effectiveListId { return tasksService.listTitle(for: id) ?? "List" }
        return "List"
    }

    // MARK: - Date picker popover

    private var datePickerPopover: some View {
        DatePicker("", selection: Binding(
            get: { draft.dueDate ?? Date() },
            set: {
                draft.dueDate = Calendar.current.startOfDay(for: $0)
                showDatePicker = false   // close as soon as a day is picked
            }
        ), displayedComponents: .date)
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(Theme.accent)
        .padding(Theme.spaceS)
        .fixedSize()
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
                            .contextMenu { listMenu(list) }
                        }
                        Button { newListText = ""; showNewList = true } label: {
                            Image(systemName: "plus").font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Theme.spaceS).padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .help("New list")
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

    /// Right-click options on a list tab / section header.
    @ViewBuilder
    private func listMenu(_ list: TaskList) -> some View {
        Button("Rename…") { renamingList = list; renameText = list.title }
        if tasksService.canMoveList(list, by: -1) {
            Button { tasksService.moveList(list, by: -1) } label: { Label("Move left", systemImage: "arrow.left") }
        }
        if tasksService.canMoveList(list, by: 1) {
            Button { tasksService.moveList(list, by: 1) } label: { Label("Move right", systemImage: "arrow.right") }
        }
        Divider()
        Button {
            Task { await tasksService.clearCompleted(listId: list.id) }
        } label: { Label("Clear completed", systemImage: "checkmark.circle") }
        Divider()
        Button(role: .destructive) {
            if panelFilter == .list(list.id) { panelFilter = .today }
            // Clear selections and collapsed state for this list
            selectedTaskIDs.removeAll()
            collapsedGroups.remove(list.id)
            Task { await tasksService.deleteList(list) }
        } label: { Label("Delete list", systemImage: "trash") }
    }

    // MARK: - Controls (sort + refresh + ⋯), parity with the popover

    private var controlsCluster: some View {
        HStack(spacing: Theme.spaceS) {
            Button { openSearch() } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)

            Menu {
                ForEach(GoogleTasksService.SortOrder.allCases, id: \.self) { order in
                    Button {
                        tasksService.sortOrder = order
                    } label: {
                        Label(order.label, systemImage: tasksService.sortOrder == order ? "checkmark" : order.icon)
                    }
                }
                Divider()
                Button {
                    groupByDate.toggle()
                    if groupByDate { groupByList = false }
                } label: {
                    Label("Group by date", systemImage: groupByDate ? "checkmark" : "calendar")
                }
                if panelFilter.isSmart {
                    Button {
                        groupByList.toggle()
                        if groupByList { groupByDate = false }
                    } label: {
                        Label("Group by list", systemImage: groupByList ? "checkmark" : "rectangle.3.group")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 12))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)

            if tasksService.isLoading {
                ProgressView().controlSize(.mini)
            }

            Menu {
                Button("Refresh now") { Task { await tasksService.fetchTaskLists() } }
                Divider()
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

    // MARK: - Empty state (context-aware)

    private struct EmptyInfo { let icon: String; let title: String; let subtitle: String? }

    private var emptyInfo: EmptyInfo {
        if tasksService.isLoading && tasksService.taskLists.isEmpty {
            return .init(icon: "arrow.clockwise", title: "Loading…", subtitle: nil)
        }
        if tasksService.taskLists.isEmpty {
            return .init(icon: "tray", title: "No lists yet",
                         subtitle: "Create one with the + next to the tabs.")
        }
        if showSearch && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return .init(icon: "magnifyingglass", title: "No matches",
                         subtitle: "No tasks match “\(searchText)”.")
        }
        switch panelFilter {
        case .today:
            return .init(icon: "checkmark.circle", title: "All clear for today",
                         subtitle: "Nothing due today or overdue.")
        case .upcoming:
            return .init(icon: "calendar", title: "Nothing upcoming",
                         subtitle: "No tasks with a due date.")
        case .all:
            return .init(icon: "checkmark.circle", title: "All done",
                         subtitle: "Add a task above to get started.")
        case .list(let id):
            let name = tasksService.listTitle(for: id) ?? "this list"
            return .init(icon: "checkmark.circle", title: "“\(name)” is empty",
                         subtitle: "Add a task above to get started.")
        }
    }

    private var emptyState: some View {
        let info = emptyInfo
        return VStack(spacing: Theme.spaceS) {
            Image(systemName: info.icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(info.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            if let subtitle = info.subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.spaceL)
    }

    // MARK: - Task list

    @ViewBuilder
    private var taskListSection: some View {
        if displayRows.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Active tasks section
                    if isGroupedByDate {
                        ForEach(tasksService.groupedByDate(activeTasks)) { group in
                            groupHeader(title: group.title, color: dateGroupColor(group.key),
                                        count: group.rows.count, key: "date:" + group.key)
                            if !collapsedGroups.contains("date:" + group.key) {
                                // Grouped by date: show only list badge (date is in the header)
                                ForEach(group.rows) { taskRow($0, showListBadge: panelFilter.isSmart || showSearch, showDateBadge: false)
                                    .id(group.rows.first?.task.id ?? "" + $0.task.id)
                                }
                            }
                        }
                    } else if isGroupedByList {
                        ForEach(tasksService.grouped(activeTasks)) { group in
                            groupHeader(title: group.title, color: tasksService.listColor(for: group.listId),
                                        count: group.rows.count, key: group.listId,
                                        list: tasksService.taskLists.first { $0.id == group.listId })
                            if !collapsedGroups.contains(group.listId) {
                                // Grouped by list: show only date badge (list is in the header)
                                ForEach(group.rows) { taskRow($0, showListBadge: false, showDateBadge: true)
                                    .id(group.listId + $0.task.id)
                                }
                            }
                        }
                    } else {
                        // No grouping: show both badges
                        ForEach(activeTasks) { taskRow($0, showListBadge: panelFilter.isSmart || showSearch, showDateBadge: true)
                            .id($0.task.id)
                        }
                    }

                    // Completed tasks section
                    if !completedTasks.isEmpty {
                        completedSection
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: activeTasks.count)
                .animation(.easeInOut(duration: 0.25), value: completedTasks.count)
                .padding(.bottom, Theme.spaceS)
            }
            .frame(maxHeight: .infinity)
            .focusable()
            .focused($listFocused)
            .modifier(ListNavKeyHandler(
                isAnyTaskBeingEdited: isAnyTaskBeingEdited,
                onUp: { cursorIndex = max(0, cursorIndex - 1) },
                onDown: { cursorIndex = min(visibleRows.count - 1, cursorIndex + 1) },
                onToggleSelect: { if let t = cursorTask { toggleSelection(t.id) } },
                onComplete: { runOnTargets { await tasksService.completeTasks($0) } },
                onDelete: { runOnTargets { await tasksService.deleteTasks($0) } },
                onSelectAll: { selectedTaskIDs = Set(visibleRows.map(\.task.id)) },
                onEdit: {
                    // TODO: Expand cursor task for editing
                    // For now, just select it (expansion handled by tap)
                },
                onExit: { exitListNavigation() }
            ))
        }
    }

    private func taskRow(_ ordered: GoogleTasksService.OrderedTask, showListBadge: Bool, showDateBadge: Bool = true) -> some View {
        let isCursor = listFocused && cursorTask?.id == ordered.task.id
        let isSelected = selectedTaskIDs.contains(ordered.task.id)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                        .padding(.leading, Theme.spaceS)
                        .transition(.scale.combined(with: .opacity))
                }
                TaskRowView(task: ordered.task, isChild: ordered.isChild,
                           showListBadge: showListBadge, showDateBadge: showDateBadge,
                           isBeingEdited: $isAnyTaskBeingEdited)
            }
            Divider().padding(.leading, ordered.isChild ? 64 : 40)
        }
        .background(isCursor ? Theme.accent.opacity(0.18)
                    : isSelected ? Theme.accent.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isCursor)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded {
            toggleSelection(ordered.task.id)
        })
    }

    /// Collapsible section header (used by both list and date grouping).
    private func groupHeader(title: String, color: Color, count: Int, key: String, list: TaskList? = nil) -> some View {
        let collapsed = collapsedGroups.contains(key)
        return Button {
            if collapsed { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)

                // Badge capsule with color background
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.15))
                .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, Theme.spaceM)
            .padding(.top, Theme.spaceM)
            .padding(.bottom, Theme.spaceXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let list { listMenu(list) }
        }
    }

    /// Completed tasks section (collapsible, TickTick-style)
    private var completedSection: some View {
        VStack(spacing: 0) {
            // Completed header
            Button {
                completedCollapsed.toggle()
                UserDefaults.standard.set(completedCollapsed, forKey: DefaultsKey.completedSectionCollapsed)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: completedCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                        Text("Completed")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(completedTasks.count)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.08))
                    .clipShape(Capsule())

                    Spacer()
                }
                .padding(.horizontal, Theme.spaceM)
                .padding(.top, Theme.spaceM)
                .padding(.bottom, Theme.spaceXS)
            }
            .buttonStyle(.plain)

            // Completed tasks (hidden when collapsed)
            if !completedCollapsed {
                ForEach(completedTasks) { taskRow($0, showListBadge: panelFilter.isSmart || showSearch, showDateBadge: true) }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Semantic color for a date bucket.
    private func dateGroupColor(_ key: String) -> Color {
        switch key {
        case "overdue":  return Theme.danger
        case "today":    return Theme.dateChip
        case "tomorrow": return Theme.accent
        default:         return .secondary
        }
    }

    // MARK: - Name

    private var nameField: some View {
        TextField("", text: $draft.name, prompt: Text("Task name  ·  # list  ·  !4dias"))
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .medium))
            .focused($nameFocused)
            .modifier(CommandKeyHandler(
                suggestionsVisible: anySuggestionsVisible,
                onShiftReturn: { notesFocused = true },
                onUp: { moveSuggestion(-1) },
                onDown: { moveSuggestion(1) },
                onAcceptSuggestion: { _ = acceptSuggestion() },
                onTabToList: { enterListNavigation() }
            ))
            .onChange(of: draft.name) { _ in
                suggestionIndex = 0
                commitCompletedTokens()
            }
            .onSubmit {
                // Enter accepts the highlighted suggestion, else adds the task.
                // (Shift+Enter jumps to the description; ⌘Enter adds via the button.)
                if !acceptSuggestion() { submit() }
            }
    }

    /// Accept the highlighted `#`/`!` suggestion if a dropdown is open.
    @discardableResult
    private func acceptSuggestion() -> Bool {
        if showListSuggestions, listSuggestions.indices.contains(suggestionIndex) {
            selectList(listSuggestions[suggestionIndex]); return true
        }
        if showDateSuggestions, dateSuggestions.indices.contains(suggestionIndex) {
            selectDate(dateSuggestions[suggestionIndex]); return true
        }
        return false
    }

    private func moveSuggestion(_ delta: Int) {
        let count = showListSuggestions ? min(listSuggestions.count, 5) : dateSuggestions.count
        guard count > 0 else { return }
        suggestionIndex = max(0, min(count - 1, suggestionIndex + delta))
    }

    // MARK: - List keyboard navigation (Tab from the input)

    private func enterListNavigation() {
        guard !visibleRows.isEmpty else { return }
        cursorIndex = min(max(cursorIndex, 0), visibleRows.count - 1)
        nameFocused = false
        listFocused = true
    }

    private func exitListNavigation() {
        clearSelection()
        listFocused = false
        nameFocused = true
    }

    /// Reset cursor and prune selection to visible rows when the view changes.
    private func resetNavigation() {
        cursorIndex = 0
        selectedTaskIDs.formIntersection(Set(visibleRows.map(\.task.id)))
    }

    private func toggleSelection(_ id: String) {
        if selectedTaskIDs.contains(id) { selectedTaskIDs.remove(id) } else { selectedTaskIDs.insert(id) }
    }

    private func clearSelection() { selectedTaskIDs.removeAll() }

    // MARK: - Bulk action bar (multi-select)

    private var bulkActionBar: some View {
        HStack(spacing: Theme.spaceM) {
            Text("\(selectedTasks.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Button { runOnTargets { await tasksService.completeTasks($0) } } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) { runOnTargets { await tasksService.deleteTasks($0) } } label: {
                Label("Delete", systemImage: "trash")
            }

            Menu {
                Button("Today") { runOnTargets { await tasksService.setDueDate($0, to: Calendar.current.startOfDay(for: Date())) } }
                Button("Tomorrow") { runOnTargets { await tasksService.setDueDate($0, to: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))) } }
                Button("Pick date…") { bulkDate = Date(); showBulkDatePicker = true }
                Divider()
                Button("Clear date") { runOnTargets { await tasksService.setDueDate($0, to: nil) } }
            } label: { Label("Date", systemImage: "calendar") }
                .fixedSize()
                .popover(isPresented: $showBulkDatePicker, arrowEdge: .bottom) {
                    VStack(spacing: Theme.spaceS) {
                        DatePicker("", selection: $bulkDate, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden().tint(Theme.accent)
                        Button("Apply") {
                            let d = Calendar.current.startOfDay(for: bulkDate)
                            runOnTargets { await tasksService.setDueDate($0, to: d) }
                            showBulkDatePicker = false
                        }
                        .buttonStyle(CapsuleButton())
                    }
                    .padding(Theme.spaceM).fixedSize()
                }

            if tasksService.taskLists.count > 1 {
                Menu {
                    ForEach(tasksService.taskLists) { list in
                        Button(list.title) { runOnTargets { await tasksService.moveTasks($0, toList: list.id) } }
                    }
                } label: { Label("Move", systemImage: "tray.and.arrow.up") }
                    .fixedSize()
            }

            Spacer()

            Button("Done") { clearSelection() }
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.spaceM)
        .padding(.vertical, Theme.spaceS)
    }

    /// Run a batch action on the current selection, or the cursor row if none.
    private func runOnTargets(_ op: @escaping ([GTask]) async -> Void) {
        let targets = selectedTaskIDs.isEmpty ? [cursorTask].compactMap { $0 } : selectedTasks
        guard !targets.isEmpty else { return }
        clearSelection()
        Task { await op(targets) }
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
                    .background(index == suggestionIndex ? Theme.accentSoft : Color.clear)
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
    /// Pick a list from the autocomplete: drop the partial `#fragment` and pin
    /// the list (it shows as the colored chip, not as text).
    private func selectList(_ list: TaskList) {
        removeLastWord()
        draft.listId = list.id
        nameFocused = true
    }

    /// Remove the last (in-progress) word, keeping a trailing space to continue.
    private func removeLastWord() {
        var parts = draft.name.components(separatedBy: " ")
        if !parts.isEmpty { parts.removeLast() }
        draft.name = parts.joined(separator: " ")
        if !draft.name.isEmpty && !draft.name.hasSuffix(" ") { draft.name += " " }
    }

    /// When the user finishes a `#list`/`!date` token with a trailing space,
    /// turn that just-finished word into its colored chip and strip it from the
    /// text. Only the word immediately before the trailing space is considered,
    /// and `#list` requires an EXACT (space-insensitive) match so a partial like
    /// `#My ` never grabs a list called "My List".
    private func commitCompletedTokens() {
        guard draft.name.hasSuffix(" ") else { return }
        var parts = draft.name.components(separatedBy: " ")
        parts.removeLast()                       // the empty piece after the space
        guard let raw = parts.last, raw.count > 1 else { return }

        if raw.hasPrefix("#"), let list = exactList(String(raw.dropFirst())) {
            draft.listId = list.id
            dropLastTokenKeepingSpace()
        } else if raw.hasPrefix("!"), let date = QuickAddParser.parse(raw).dueDate {
            draft.dueDate = date
            dropLastTokenKeepingSpace()
        }
    }

    /// Exact list match (ignoring spaces/case) — stricter than the autocomplete.
    private func exactList(_ name: String) -> TaskList? {
        let needle = name.replacingOccurrences(of: " ", with: "").lowercased()
        guard !needle.isEmpty else { return nil }
        return tasksService.taskLists.first {
            $0.title.replacingOccurrences(of: " ", with: "").lowercased() == needle
        }
    }

    /// Remove the finished word (the one before the trailing space), keep a space.
    private func dropLastTokenKeepingSpace() {
        var parts = draft.name.components(separatedBy: " ")
        parts.removeLast()                       // empty piece after trailing space
        if !parts.isEmpty { parts.removeLast() } // the finished token
        draft.name = parts.joined(separator: " ")
        if !draft.name.isEmpty && !draft.name.hasSuffix(" ") { draft.name += " " }
    }


    // MARK: - !date autocomplete dropdown

    private var dateSuggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(dateSuggestions.enumerated()), id: \.element.id) { index, option in
                Button {
                    selectDate(option)
                } label: {
                    HStack(spacing: Theme.spaceS) {
                        Image(systemName: option.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(option.date == nil ? Theme.accent : .secondary)
                            .frame(width: 16)
                        Text(option.label).font(.system(size: 14))
                        Spacer()
                        if let d = option.date {
                            Text(dueLabel(d)).font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, Theme.spaceM)
                    .padding(.vertical, Theme.spaceS + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(index == suggestionIndex ? Theme.accentSoft : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .padding(.top, Theme.spaceS)
    }

    /// Apply a date option: set the due date (or open the picker for Custom),
    /// then strip the `!token` from the text since the date now shows as a chip.
    private func selectDate(_ option: DateOption) {
        removeBangToken()
        if let date = option.date {
            draft.dueDate = date
        } else {
            showDatePicker = true   // Custom…
        }
        nameFocused = true
    }

    private func removeBangToken() {
        var tokens = draft.name.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if let last = tokens.last, last.hasPrefix("!") { tokens.removeLast() }
        draft.name = tokens.joined(separator: " ")
        if !draft.name.isEmpty && !draft.name.hasSuffix(" ") { draft.name += " " }
    }

    private func quickDateChip(_ label: String, date: Date?) -> some View {
        let isSelected = draft.dueDate != nil && date != nil && Calendar.current.isDate(draft.dueDate!, inSameDayAs: date!)
        return Button {
            draft.dueDate = date
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize()
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
        .fixedSize()
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit, let listId = effectiveListId else { return }
        let title = parsed.title
        let due = effectiveDueDate
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            await tasksService.addTask(title: title, notes: notes.isEmpty ? nil : notes, due: due, to: listId)
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

/// Keyboard handling for the quick-add title field:
/// - Shift+Return → jump to the description.
/// - ↑/↓ → move the `#list` autocomplete selection (when visible).
/// (Plain Return is handled by onSubmit; ⌘Return adds via the Add button.)
/// In the description: Enter adds the task; Shift+Enter inserts a newline.
private struct DescriptionKeyHandler: ViewModifier {
    let onEnter: () -> Void
    let onShiftEnter: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress { press in
                guard press.key == .return else { return .ignored }
                if press.modifiers.contains(.shift) {
                    onShiftEnter(); return .handled
                }
                onEnter(); return .handled
            }
        } else {
            content
        }
    }
}

private struct CommandKeyHandler: ViewModifier {
    let suggestionsVisible: Bool
    let onShiftReturn: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onAcceptSuggestion: () -> Void
    let onTabToList: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress { press in
                if press.key == .return, press.modifiers.contains(.shift) {
                    onShiftReturn(); return .handled
                }
                if suggestionsVisible, press.key == .upArrow {
                    onUp(); return .handled
                }
                if suggestionsVisible, press.key == .downArrow {
                    onDown(); return .handled
                }
                if press.key == .tab {
                    // Tab accepts an open suggestion, else moves focus to the list.
                    if suggestionsVisible { onAcceptSuggestion() } else { onTabToList() }
                    return .handled
                }
                return .ignored
            }
        } else {
            content
        }
    }
}

/// Keyboard handling for the task list when it has focus (Tab from the input):
/// ↑/↓ move the cursor, Space toggles selection, Return completes, Delete
/// removes, E expands for edit, ⌘A selects all, Esc/Tab returns to the input.
private struct ListNavKeyHandler: ViewModifier {
    let isAnyTaskBeingEdited: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onToggleSelect: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void
    let onSelectAll: () -> Void
    let onEdit: () -> Void
    let onExit: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress { press in
                switch press.key {
                case .upArrow:   onUp(); return .handled
                case .downArrow: onDown(); return .handled
                case .return:
                    // Don't complete task if any task is being edited
                    if isAnyTaskBeingEdited { return .ignored }
                    onComplete()
                    return .handled
                case .delete, .deleteForward: onDelete(); return .handled
                case .escape, .tab: onExit(); return .handled
                default:
                    if press.modifiers.contains(.command), press.characters == "a" {
                        onSelectAll(); return .handled
                    } else if press.characters == "e" {
                        onEdit(); return .handled
                    }
                    return .ignored
                }
            }
        } else {
            content
        }
    }
}
