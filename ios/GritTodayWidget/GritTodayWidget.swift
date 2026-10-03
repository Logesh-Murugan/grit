import WidgetKit
import SwiftUI
import AppIntents

struct TodayEntry: TimelineEntry { let date: Date; let snapshot: GritWidgetSnapshot? }
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: GritWidgetSnapshot(workspace: "preview",
            day: GritWidgetStore.todayKey(), tasks: [
                GritWidgetTask(id: "preview", title: "Make time for what matters", priority: 2, scheduled: nil)]))
    }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) :
            TodayEntry(date: Date(), snapshot: GritWidgetStore.read().snapshot))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: now)) ?? midnight
        // The midnight entry clears yesterday's task actions even if the system
        // postpones the next refresh. The app refreshes the actual next-day plan.
        completion(Timeline(entries: [
            TodayEntry(date: now, snapshot: GritWidgetStore.read().snapshot),
            TodayEntry(date: nextDay, snapshot: nil)],
            policy: .after(min(nextDay, now.addingTimeInterval(900)))))
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var textSize
    private let coral = Color(red: 0.79, green: 0.40, blue: 0.32)
    private var taskLimit: Int {
        if textSize.isAccessibilitySize { return family == .systemLarge ? 2 : 1 }
        return family == .systemSmall ? 1 : family == .systemLarge ? 5 : 2
    }
    private var isToday: Bool { entry.snapshot?.day == GritWidgetStore.todayKey(entry.date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today", systemImage: "sun.max.fill")
                    .font(.headline).foregroundStyle(coral)
                Spacer(minLength: 4)
                if !textSize.isAccessibilitySize {
                    Text(isToday && (entry.snapshot?.tasks.count ?? 0) > taskLimit
                         ? "\(entry.snapshot!.tasks.count) tasks" : "grit")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if isToday, let tasks = entry.snapshot?.tasks, !tasks.isEmpty {
                ForEach(Array(tasks.prefix(taskLimit))) { task in
                    HStack(spacing: 8) {
                        Button(intent: CompleteGritTask(taskId: task.id, workspace: entry.snapshot?.workspace ?? "", scheduled: task.scheduled)) {
                            Image(systemName: "circle").font(.title2)
                                .foregroundStyle(task.priority == 1 ? coral : Color.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Complete \(task.title)")
                        Text(task.title).font(.subheadline.weight(.medium))
                            .lineLimit(2).privacySensitive()
                    }
                }
                Spacer(minLength: 0)
                if family == .systemLarge && tasks.count > taskLimit && !textSize.isAccessibilitySize {
                    Text("+\(tasks.count - taskLimit) more in GRIT")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Spacer(minLength: 0)
                Image(systemName: isToday ? "checkmark.circle" : "sunrise")
                    .font(.title2).foregroundStyle(coral).accessibilityHidden(true)
                Text(isToday ? "A little breathing room." : "A fresh start.")
                    .font(.subheadline.weight(.semibold))
                if family != .systemSmall || !textSize.isAccessibilitySize {
                    Text(isToday ? "Tap to plan one thing that matters." : "Open GRIT to update Today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }.containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(URL(string: "grit://today"))
    }
}

@main
struct GritTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GritToday", provider: TodayProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today in GRIT")
            .description("Your next steps, with one-tap completion. Includes overdue tasks.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
