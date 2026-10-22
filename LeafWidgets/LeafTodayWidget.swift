import SwiftUI
import WidgetKit

/// Today's reading on the Home Screen, in StandBy and on the Lock Screen: minutes left and the page to start from, the
/// week, the next books with their likely finish, and Read or Steep a tap away. While a session or a pot is going it
/// becomes the timer, drawn by the system so nothing updates per second. The app writes the snapshot after every
/// change and reloads the timeline (`Leaf/Services/WidgetFeed.swift`); the views are in
/// `LiveActivityShared/LeafWidgetViews.swift`.
struct LeafTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LeafWidgetStore.todayKind, provider: LeafTodayProvider()) { entry in
            LeafTodayEntryView(entry: entry)
        }
        .configurationDisplayName("Today’s reading")
        .description("Today’s goal, your next reading time, and Begin reading a tap away.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LeafTodayEntry: TimelineEntry {
    let date: Date
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt
}

struct LeafTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> LeafTodayEntry {
        let sample = LeafWidgetSnapshot.sample()
        return LeafTodayEntry(date: Date(), snapshot: sample, phase: .today, art: LeafWidgetArt())
    }

    func getSnapshot(in context: Context, completion: @escaping (LeafTodayEntry) -> Void) {
        // The gallery shows a lived-in evening until the reader has a book of their own.
        let stored = LeafWidgetStore.read()
        if context.isPreview, stored?.current == nil {
            completion(placeholder(in: context))
            return
        }
        completion(Self.entries(from: stored ?? .empty, now: Date(), family: context.family).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LeafTodayEntry>) -> Void) {
        let snapshot = LeafWidgetStore.read() ?? .empty
        let entries = Self.entries(from: snapshot, now: Date(), family: context.family)
        // After the last change (midnight at the latest) ask again; the app reloads sooner whenever anything changes.
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Now, then each moment the widget changes by itself: the goal crossed, the tea ready or cold, midnight.
    static func entries(from snapshot: LeafWidgetSnapshot, now: Date, family: WidgetFamily) -> [LeafTodayEntry] {
        let isAccessory = [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
        let art = isAccessory ? LeafWidgetArt() : LeafWidgetArt.load(for: snapshot, includeUpNext: family == .systemLarge)
        return ([now] + snapshot.changes(after: now)).map { date in
            let shown = snapshot.at(date)
            return LeafTodayEntry(date: date, snapshot: shown, phase: shown.phase(at: date), art: art)
        }
    }
}

struct LeafTodayEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LeafTodayEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isAccessory {
                    Color.clear
                } else {
                    LeafWidgetBackground()
                }
            }
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium: LeafWidgetMedium(snapshot: entry.snapshot, phase: entry.phase, art: entry.art, now: entry.date)
        case .systemLarge: LeafWidgetLarge(snapshot: entry.snapshot, phase: entry.phase, art: entry.art, now: entry.date)
        case .accessoryCircular: LeafWidgetCircular(snapshot: entry.snapshot, phase: entry.phase)
        case .accessoryRectangular: LeafWidgetRectangular(snapshot: entry.snapshot, phase: entry.phase, now: entry.date)
        case .accessoryInline: LeafWidgetInline(snapshot: entry.snapshot, phase: entry.phase, now: entry.date)
        default: LeafWidgetSmall(snapshot: entry.snapshot, phase: entry.phase, art: entry.art, now: entry.date)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    LeafTodayWidget()
} timeline: {
    LeafTodayEntry(date: .now, snapshot: .sample(), phase: .today, art: LeafWidgetArt())
}

#Preview("Medium", as: .systemMedium) {
    LeafTodayWidget()
} timeline: {
    LeafTodayEntry(date: .now, snapshot: .sample(), phase: .today, art: LeafWidgetArt())
}

#Preview("Large", as: .systemLarge) {
    LeafTodayWidget()
} timeline: {
    LeafTodayEntry(date: .now, snapshot: .sample(), phase: .today, art: LeafWidgetArt())
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LeafTodayWidget()
} timeline: {
    LeafTodayEntry(date: .now, snapshot: .sample(), phase: .today, art: LeafWidgetArt())
}
