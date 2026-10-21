import SwiftUI
import WidgetKit

/// The Timer widget: while a reading session or a tea steep is running on the wrist, its countdown (or count-up) on
/// the face and in the Smart Stack, drawn by the system with `Text(timerInterval:)` so nothing updates per second.
/// It wants the Smart Stack's top while it runs, falls back once the timer is over, and shows today's reading the rest
/// of the time. A session started on the phone is shown by the phone's mirrored Live Activity instead, so this stays
/// out of the way for it (the watch app decides; see `LiveTimerRules`).
struct LeafTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationStore.timerKind, provider: TimerProvider()) { entry in
            TimerEntryView(entry: entry)
                .containerBackground(ComplicationPalette.deep.gradient, for: .widget)
        }
        .configurationDisplayName("Reading timer")
        .description("Your cup of reading or your tea, counting down while it runs.")
        .supportedFamilies([.accessoryRectangular, .accessoryCorner, .accessoryCircular, .accessoryInline])
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let snapshot: ComplicationSnapshot
    /// The timer and its state at `date`, or nil for today's reading.
    let timer: ComplicationTimer?
    let state: String
    let relevance: TimelineEntryRelevance?
}

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(date: Date(), snapshot: .sample, timer: TimerSamples.reading(), state: "running", relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let snapshot = ComplicationStore.read() ?? .sample
        completion(TimerTimeline.entries(from: snapshot, now: Date()).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let snapshot = ComplicationStore.read() ?? .empty
        let entries = TimerTimeline.entries(from: snapshot, now: Date())
        // Once the timer has gone there is nothing more to change until the app writes a new snapshot.
        completion(Timeline(entries: entries, policy: .never))
    }
}

/// The timer's phases as entries, then today's reading once it has expired. With no timer, just today's reading.
enum TimerTimeline {
    static func entries(from snapshot: ComplicationSnapshot, now: Date) -> [TimerEntry] {
        let today = snapshot.at(now)
        guard let timer = snapshot.timer, timer.expiresAt > now, !timer.phases.isEmpty else {
            return [TimerEntry(date: now, snapshot: today, timer: nil, state: "", relevance: TimelineEntryRelevance(score: 0))]
        }
        var entries: [TimerEntry] = []
        for (index, phase) in timer.phases.enumerated() {
            let from = max(phase.from, now)
            let until = index + 1 < timer.phases.count ? timer.phases[index + 1].from : timer.expiresAt
            guard until > from else { continue }
            entries.append(TimerEntry(
                date: from,
                snapshot: snapshot.at(from),
                timer: timer,
                state: phase.state,
                relevance: TimelineEntryRelevance(score: Float(phase.relevance), duration: until.timeIntervalSince(from))
            ))
        }
        entries.append(TimerEntry(date: timer.expiresAt, snapshot: snapshot.at(timer.expiresAt), timer: nil, state: "", relevance: TimelineEntryRelevance(score: 0)))
        return entries
    }
}

struct TimerEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimerEntry

    var body: some View {
        if let timer = entry.timer {
            switch family {
            case .accessoryCorner: TimerCorner(timer: timer, state: entry.state)
            case .accessoryCircular: TimerCircular(timer: timer, state: entry.state)
            case .accessoryInline: TimerInline(timer: timer, state: entry.state)
            default: TimerRectangular(timer: timer, state: entry.state)
            }
        } else {
            ComplicationEntryView(entry: ComplicationEntry(date: entry.date, snapshot: entry.snapshot, relevance: nil))
        }
    }
}

#Preview("Timer · rectangular", as: .accessoryRectangular) {
    LeafTimerWidget()
} timeline: {
    TimerEntry(date: .now, snapshot: .sample, timer: TimerSamples.reading(), state: "running", relevance: nil)
    TimerEntry(date: .now, snapshot: .sample, timer: TimerSamples.steeping(), state: "running", relevance: nil)
    TimerEntry(date: .now, snapshot: .sample, timer: TimerSamples.steeping(), state: "reached", relevance: nil)
}
