import SwiftUI
import WidgetKit

/// Hands the complications what they draw, from the watch's snapshot, and reloads them only when that changed.
enum ComplicationFeed {
    /// `day` is the day the snapshot's minutes belong to (WatchStore.minutesDay); `steep` the pot on the wrist.
    static func publish(_ snapshot: WatchSnapshot, day: Date, steep: SteepTimer? = nil, goalSeconds: Double? = nil, now: Date = Date()) {
        var next = ComplicationSnapshot(snapshot, day: day, now: now)
        next.timer = liveTimer(snapshot, steep: steep, goalSeconds: goalSeconds, now: now).map { ComplicationTimer($0, now: now) }
        // Once the day's goal is met the phone plans no more reading times, so it sends none; the face keeps the
        // last ones it knew, so tomorrow's card still rises around them.
        if next.slotMinutes.isEmpty, next.isReadingDay, let previous = ComplicationStore.read() {
            next.slotMinutes = previous.slotMinutes
        }
        if ComplicationStore.write(next) {
            WidgetCenter.shared.reloadTimelines(ofKind: ComplicationStore.kind)
            WidgetCenter.shared.reloadTimelines(ofKind: ComplicationStore.timerKind)
        }
    }

    /// The timer the watch should show, if any: the session (when no phone Live Activity already shows it on the
    /// wrist), else a pot steeping here. `goalSeconds` is the session's goal as the store works it out.
    static func liveTimer(_ snapshot: WatchSnapshot, steep: SteepTimer?, goalSeconds: Double?, now: Date) -> LiveTimer? {
        if let session = snapshot.activeSession {
            let tea = session.teaID.flatMap { id in snapshot.tea?.id == id ? snapshot.tea?.name : nil }
            let timer = LiveTimer(
                kind: .reading,
                origin: session.origin == .watch ? .watch : .phone,
                sessionID: session.id,
                start: session.startedAt.addingTimeInterval(session.pausedSeconds),
                pausedElapsed: session.isPaused ? session.elapsed(at: now) : nil,
                goalSeconds: goalSeconds,
                title: snapshot.book(session.bookID)?.title,
                teaName: tea
            )
            guard LiveTimerRules.watchShowsCard(for: timer, phoneActivitySessionID: snapshot.liveActivitySessionID),
                  !timer.isExpired(at: now) else { return nil }
            return timer
        }
        if let steep {
            let timer = LiveTimer(
                kind: .steep, origin: .watch, sessionID: nil, start: steep.startedAt, pausedElapsed: nil,
                goalSeconds: Double(steep.tea.steepSeconds), title: nil, teaName: steep.tea.name
            )
            return timer.isExpired(at: now) ? nil : timer
        }
        return nil
    }
}

extension ComplicationTimer {
    init(_ timer: LiveTimer, now: Date) {
        self.init(
            isSteep: timer.kind == .steep,
            start: timer.start,
            pausedElapsed: timer.pausedElapsed,
            goalSeconds: timer.goalSeconds,
            title: timer.title,
            teaName: timer.teaName,
            phases: timer.phases(from: now).map { Phase(from: $0.from, state: $0.state.rawValue, relevance: $0.relevance) },
            expiresAt: timer.expiresAt
        )
    }
}

extension ComplicationSnapshot {
    init(_ snapshot: WatchSnapshot, day: Date, now: Date = Date(), calendar: Calendar = .current) {
        let first = snapshot.today.first
        let book = first.flatMap { snapshot.book($0.bookID) } ?? snapshot.reading.first
        // Only a session the watch is timing counts up on the face; the watch may sleep through a phone's session
        // and never hear that it ended.
        let live = snapshot.activeSession.flatMap { session -> Date? in
            session.isPaused || session.origin != .watch ? nil : now.addingTimeInterval(-session.elapsed(at: now))
        }
        self.init(
            day: calendar.startOfDay(for: day),
            dailyMinutes: snapshot.dailyMinutes,
            minutesReadToday: snapshot.minutesReadToday,
            isReadingDay: snapshot.isReadingDay,
            title: book?.title,
            nextPage: book.flatMap { book -> Int? in
                guard book.currentPage < book.pages else { return nil }
                let next = book.currentPage + 1
                if let first, first.bookID == book.id { return min(book.pages, max(first.fromPage, next)) }
                return next
            },
            slotMinutes: snapshot.slots.map(\.minuteOfDay),
            liveSince: live
        )
    }
}

#if DEBUG
/// `-LeafScreen complications`: the complications drawn in the app, since a CI simulator has no face to put them on.
/// The face tints them; this shows their shapes and words in full colour.
struct ComplicationGallery: View {
    private var states: [(String, ComplicationSnapshot)] {
        var reading = ComplicationSnapshot.sample
        reading.liveSince = Date().addingTimeInterval(-9 * 60 - 41)
        var done = ComplicationSnapshot.sample
        done.minutesReadToday = 31
        return [("Today", .sample), ("Reading", reading), ("Done", done)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(states, id: \.0) { name, snapshot in
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ComplicationCircular(snapshot: snapshot)
                            .frame(width: 50, height: 50)
                        ComplicationInline(snapshot: snapshot)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    ComplicationRectangular(snapshot: snapshot)
                        .padding(8)
                        .background(ComplicationPalette.deep.gradient, in: .rect(cornerRadius: 14))
                }
            }
        }
    }
}

/// `-LeafScreen timers`: the Timer widget's faces in each state, since a CI simulator has no face to put them on.
struct TimerGallery: View {
    private struct Sample: Identifiable {
        let id: String
        let timer: ComplicationTimer
        let state: String
    }

    private var samples: [Sample] {
        [
            Sample(id: "Reading", timer: TimerSamples.reading(), state: "running"),
            Sample(id: "Paused", timer: TimerSamples.paused(), state: "paused"),
            Sample(id: "Steeping", timer: TimerSamples.steeping(), state: "running"),
            Sample(id: "Tea ready", timer: TimerSamples.steeping(), state: "reached"),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(samples) { sample in
                    let timer = sample.timer
                    let state = sample.state
                    Text(sample.id).font(.caption2).foregroundStyle(.secondary)
                    TimerRectangular(timer: timer, state: state)
                        .padding(8)
                        .background(ComplicationPalette.deep.gradient, in: .rect(cornerRadius: 14))
                    HStack(spacing: 10) {
                        TimerCircular(timer: timer, state: state)
                            .frame(width: 50, height: 50)
                        TimerInline(timer: timer, state: state)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
#endif
