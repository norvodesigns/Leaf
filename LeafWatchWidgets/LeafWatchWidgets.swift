import SwiftUI
import WidgetKit

/// The watch's complications and Smart Stack card: today's minutes and the page to start from, from the snapshot the
/// watch app leaves in the shared container. Most relevant in the half hour around each of your reading times.
@main
struct LeafWatchWidgets: WidgetBundle {
    var body: some Widget {
        LeafComplication()
    }
}

struct LeafComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationStore.kind, provider: ComplicationProvider()) { entry in
            ComplicationEntryView(entry: entry)
                .containerBackground(ComplicationPalette.deep.gradient, for: .widget)
        }
        .configurationDisplayName("Today's reading")
        .description("Minutes left today and the page to start from.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
    let relevance: TimelineEntryRelevance?
}

struct ComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCorner: ComplicationCorner(snapshot: entry.snapshot)
        case .accessoryRectangular: ComplicationRectangular(snapshot: entry.snapshot)
        case .accessoryInline: ComplicationInline(snapshot: entry.snapshot)
        default: ComplicationCircular(snapshot: entry.snapshot)
        }
    }
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .sample, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let snapshot = context.isPreview ? ComplicationSnapshot.sample : (ComplicationStore.read() ?? .sample)
        completion(ComplicationEntry(date: Date(), snapshot: snapshot.at(Date()), relevance: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(ComplicationTimeline.make(from: ComplicationStore.read() ?? .empty, now: Date()))
    }
}

/// Entries for the next day: now, around each reading time (where the Smart Stack should surface the card), and the
/// fresh start at midnight. The watch app reloads the timeline whenever the snapshot changes.
enum ComplicationTimeline {
    /// How long before a reading time the card becomes relevant, and for how long.
    static let lead: TimeInterval = 15 * 60
    static let window: TimeInterval = 45 * 60

    static func make(from snapshot: ComplicationSnapshot, now: Date, calendar: Calendar = .current) -> Timeline<ComplicationEntry> {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        var dates: Set<Date> = [now, tomorrow]
        for start in [today, tomorrow] {
            for minute in snapshot.slotMinutes {
                let slot = start.addingTimeInterval(TimeInterval(minute * 60))
                for date in [slot.addingTimeInterval(-lead), slot.addingTimeInterval(window - lead)] where date > now {
                    dates.insert(date)
                }
            }
        }
        let entries = dates.sorted().filter { $0 <= tomorrow.addingTimeInterval(86_400) }.map { date -> ComplicationEntry in
            let shown = snapshot.at(date, calendar: calendar)
            return ComplicationEntry(date: date, snapshot: shown, relevance: relevance(of: shown, at: date, calendar: calendar))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// High while reading and in a reading time's window, none once the day's goal is met, low otherwise.
    static func relevance(of snapshot: ComplicationSnapshot, at date: Date, calendar: Calendar) -> TimelineEntryRelevance {
        if snapshot.liveSince != nil { return TimelineEntryRelevance(score: 1, duration: window) }
        if snapshot.isGoalMet || snapshot.dailyMinutes == 0 || snapshot.isRestDay { return TimelineEntryRelevance(score: 0) }
        let start = calendar.startOfDay(for: date)
        for minute in snapshot.slotMinutes {
            let opens = start.addingTimeInterval(TimeInterval(minute * 60) - lead)
            if date >= opens && date < opens.addingTimeInterval(window) {
                return TimelineEntryRelevance(score: 0.9, duration: opens.addingTimeInterval(window).timeIntervalSince(date))
            }
        }
        return TimelineEntryRelevance(score: 0.1)
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LeafComplication()
} timeline: {
    ComplicationEntry(date: .now, snapshot: .sample, relevance: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    LeafComplication()
} timeline: {
    ComplicationEntry(date: .now, snapshot: .sample, relevance: nil)
}
