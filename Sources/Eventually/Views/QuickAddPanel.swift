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

    /// The list resolved from a `#token`, if it matches a real list. Compares
    /// ignoring spaces so an autocompleted token like `#📋Lectura` still matches
    /// a list titled "📋 Lectura".
    private var resolvedList: TaskList? {
        guard let name = parsed.listName, !name.isEmpty else { return nil }
        let needle = name.replacingOccurrences(of: " ", with: "").lowercased()
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
        .onChange(of: panelFilter) { saveLastUsed($0) }
        .onExitCommand { handleEscape() }
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
        TextField("Description (optional · markdown)", text: $draft.notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1...4)
            .focused($notesFocused)
    }

    // MARK: - Header controls (date chips + list selector + add)

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

            listSelectorChip

            Spacer()

            Button("Add task") { submit() }
                .buttonStyle(CapsuleButton(enabled: canSubmit))
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    /// List selector chip — pick the target list by click (alternative to `#`).
    private var listSelectorChip: some View {
        let active = draft.listId != nil || resolvedList != nil
        let warn = unmatchedListToken
        let tint: Color = warn ? Theme.danger : (active ? Theme.accent : .secondary)
        return Menu {
            ForEach(tasksService.taskLists) { list in
                Button(list.title) { draft.listId = list.id }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: warn ? "questionmark.circle" : "list.bullet").font(.system(size: 11))
                Text(warn ? "#\(parsed.listName!)?" : currentListName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.spaceM)
            .padding(.vertical, 5)
            .background(Capsule().fill(warn ? Theme.danger.opacity(0.14) : (active ? Theme.accentSoft : Color.clear)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(active || warn ? 0 : 0.15), lineWidth: 1))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(tint)
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
        Button(role: .destructive) {
            if panelFilter == .list(list.id) { panelFilter = .today }
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
                    if isGroupedByDate {
                        ForEach(tasksService.groupedByDate(displayRows)) { group in
                            groupHeader(title: group.title, color: dateGroupColor(group.key),
                                        count: group.rows.count, key: "date:" + group.key)
                            if !collapsedGroups.contains("date:" + group.key) {
                                ForEach(group.rows) { taskRow($0, badge: panelFilter.isSmart || showSearch) }
                            }
                        }
                    } else if isGroupedByList {
                        ForEach(tasksService.grouped(displayRows)) { group in
                            groupHeader(title: group.title, color: tasksService.listColor(for: group.listId),
                                        count: group.rows.count, key: group.listId,
                                        list: tasksService.taskLists.first { $0.id == group.listId })
                            if !collapsedGroups.contains(group.listId) {
                                ForEach(group.rows) { taskRow($0, badge: false) }
                            }
                        }
                    } else {
                        ForEach(displayRows) { taskRow($0, badge: panelFilter.isSmart || showSearch) }
                    }
                }
                .padding(.bottom, Theme.spaceS)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func taskRow(_ ordered: GoogleTasksService.OrderedTask, badge: Bool) -> some View {
        VStack(spacing: 0) {
            TaskRowView(task: ordered.task, isChild: ordered.isChild, showListBadge: badge)
            Divider().padding(.leading, ordered.isChild ? 64 : 40)
        }
    }

    /// Collapsible section header (used by both list and date grouping).
    private func groupHeader(title: String, color: Color, count: Int, key: String, list: TaskList? = nil) -> some View {
        let collapsed = collapsedGroups.contains(key)
        return Button {
            if collapsed { collapsedGroups.remove(key) } else { collapsedGroups.insert(key) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
            .modifier(ShiftReturnToNotes { notesFocused = true })
            .onSubmit {
                // Enter accepts the top autocomplete suggestion, else adds the task.
                // (Shift+Enter jumps to the description; ⌘Enter adds via the button.)
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

/// Intercepts Shift+Return to jump from the title to the description field.
/// (Plain Return adds the task; ⌘Return also adds via the Add button.)
private struct ShiftReturnToNotes: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress { press in
                if press.key == .return && press.modifiers.contains(.shift) {
                    action()
                    return .handled
                }
                return .ignored
            }
        } else {
            content
        }
    }
}
