import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct TasksEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let listName: String
}

struct WidgetTask: Identifiable {
    let id: String
    let title: String
    let isOverdue: Bool
    let isToday: Bool
    let dueLabel: String?
}

// MARK: - Provider

struct TasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        TasksEntry(
            date: Date(),
            tasks: [
                WidgetTask(id: "1", title: "Buy groceries", isOverdue: false, isToday: true, dueLabel: "Today"),
                WidgetTask(id: "2", title: "Call the dentist", isOverdue: true, isToday: false, dueLabel: "Yesterday"),
                WidgetTask(id: "3", title: "Review PR", isOverdue: false, isToday: false, dueLabel: nil),
            ],
            listName: "My Tasks"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        Task {
            let entry = await fetchTasks()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchTasks() async -> TasksEntry {
        // Reads cached tasks from App Group shared container
        guard let sharedDefaults = UserDefaults(suiteName: "group.app.tabella.Eventually"),
              let data = sharedDefaults.data(forKey: "cachedTasks"),
              let cached = try? JSONDecoder().decode([CachedTask].self, from: data)
        else {
            return TasksEntry(date: Date(), tasks: [], listName: "My Tasks")
        }

        let today = Calendar.current.startOfDay(for: Date())
        let widgetTasks = cached.prefix(5).map { t -> WidgetTask in
            var isOverdue = false
            var isToday = false
            var dueLabel: String?

            if let dueInterval = t.dueInterval {
                let due = Date(timeIntervalSince1970: dueInterval)
                isOverdue = due < today
                isToday = Calendar.current.isDateInToday(due)
                if isToday { dueLabel = "Today" }
                else if isOverdue { dueLabel = "Overdue" }
            }

            return WidgetTask(id: t.id, title: t.title, isOverdue: isOverdue, isToday: isToday, dueLabel: dueLabel)
        }

        return TasksEntry(
            date: Date(),
            tasks: Array(widgetTasks),
            listName: sharedDefaults.string(forKey: "currentListName") ?? "My Tasks"
        )
    }
}

struct CachedTask: Codable {
    let id: String
    let title: String
    let dueInterval: Double?
}

// MARK: - Widget Views

struct EventuallyWidgetEntryView: View {
    var entry: TasksEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: mediumView
        }
    }

    // Small: show count + top 2 tasks
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12, weight: .semibold))
                Text(entry.listName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(entry.tasks.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.blue)
            }

            Divider()

            ForEach(entry.tasks.prefix(3)) { task in
                taskRow(task, compact: true)
            }

            Spacer()
        }
        .padding(12)
    }

    // Medium: show more tasks
    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(.blue)
                    .font(.system(size: 13, weight: .semibold))
                Text(entry.listName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(entry.tasks.count) tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if entry.tasks.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("All done!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.tasks.prefix(5)) { task in
                    taskRow(task, compact: false)
                }
            }

            Spacer()
        }
        .padding(14)
    }

    private func taskRow(_ task: WidgetTask, compact: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .stroke(task.isOverdue ? Color.red : Color.secondary.opacity(0.4), lineWidth: 1.5)
                .frame(width: compact ? 12 : 14, height: compact ? 12 : 14)

            Text(task.title)
                .font(.system(size: compact ? 11 : 12))
                .lineLimit(1)
                .foregroundStyle(task.isOverdue ? .red : .primary)

            Spacer()

            if let label = task.dueLabel {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(task.isOverdue ? .red : .orange)
            }
        }
    }
}

// MARK: - Widget Configuration

@main
struct EventuallyWidget: Widget {
    let kind: String = "EventuallyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            if #available(macOS 14.0, *) {
                EventuallyWidgetEntryView(entry: entry)
                    .containerBackground(.background, for: .widget)
            } else {
                EventuallyWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .configurationDisplayName("Eventually")
        .description("See your Google Tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
