import SwiftUI
import WidgetKit

/// Hands the complications what they draw, from the watch's snapshot, and reloads them only when that changed.
enum ComplicationFeed {
    /// `day` is the day the snapshot's minutes belong to (WatchStore.minutesDay).
    static func publish(_ snapshot: WatchSnapshot, day: Date, now: Date = Date()) {
        var next = ComplicationSnapshot(snapshot, day: day, now: now)
        // Once the day's goal is met the phone plans no more reading times, so it sends none; the face keeps the
        // last ones it knew, so tomorrow's card still rises around them.
        if next.slotMinutes.isEmpty, next.isReadingDay, let previous = ComplicationStore.read() {
            next.slotMinutes = previous.slotMinutes
        }
        if ComplicationStore.write(next) {
            WidgetCenter.shared.reloadTimelines(ofKind: ComplicationStore.kind)
        }
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
#endif
