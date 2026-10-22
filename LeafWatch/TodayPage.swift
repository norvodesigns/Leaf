import SwiftUI

/// The first page, the nook: the phone's greeting, today's cup, the tea for the hour with "Steep and read", and the
/// day's reading times. While a pot steeps it becomes the tea timer, which hands off to a cup of reading.
struct TodayPage: View {
    @Environment(WatchStore.self) private var store
    var onOpenSession: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: store.steep == nil ? 30 : 1)) { context in
            ScrollView {
                content(now: context.date)
                    .padding(.horizontal, 2)
            }
        }
        .containerBackground(WatchTheme.accentDeep.gradient, for: .tabView)
        .navigationTitle("Leaf")
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let snapshot = store.snapshot
        if !snapshot.hasOnboarded && snapshot.reading.isEmpty {
            WatchPlaceholder(symbol: "iphone", text: "Open Leaf on your iPhone to set up your plan.")
        } else if store.activeSession == nil, let steep = store.steep {
            SteepTimerView(steep: steep, now: now, onStart: startCup)
        } else if let book = store.suggestedBook {
            VStack(alignment: .leading, spacing: 6) {
                if let greeting = snapshot.greeting {
                    Text(greeting.headline)
                        .font(WatchTheme.serif(22))
                        .foregroundStyle(WatchTheme.paper)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let subline = greeting.subline {
                        Text(subline)
                            .font(.system(size: 12))
                            .foregroundStyle(WatchTheme.inkSecondary)
                            .lineLimit(2)
                    }
                }
                HStack(alignment: .center, spacing: 10) {
                    cup(now: now)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(book.title)
                            .font(.system(.footnote, design: .serif).weight(.semibold))
                            .foregroundStyle(WatchTheme.paper)
                            .lineLimit(2)
                        if let assignment = store.assignment(for: book.id) {
                            Text(LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage))
                                .font(.system(size: 11))
                                .foregroundStyle(WatchTheme.inkSecondary)
                        }
                    }
                }
                actions(book: book, now: now)
                slots
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            WatchPlaceholder(symbol: "books.vertical", text: "Add a book in Leaf on your iPhone and it’ll appear here.")
        }
    }

    /// Today's cup: the ring of the goal with the minutes left in it.
    private func cup(now: Date) -> some View {
        let left = max(0, Double(store.snapshot.dailyMinutes) - store.minutesToday(at: now))
        return ZStack {
            GoalRing(progress: store.goalProgress(at: now), lineWidth: 5)
            if left < 0.5 {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WatchTheme.accent)
            } else {
                VStack(spacing: -3) {
                    Text("\(Int(left.rounded(.up)))")
                        .font(WatchTheme.display(20).monospacedDigit())
                        .foregroundStyle(WatchTheme.paper)
                        .contentTransition(.numericText())
                    Text("min").font(.system(size: 9)).foregroundStyle(WatchTheme.inkSecondary)
                }
            }
        }
        .frame(width: 50, height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left < 0.5 ? "Today’s goal is done" : "\(Int(left.rounded(.up))) minutes left today")
    }

    @ViewBuilder
    private func actions(book: WatchBook, now: Date) -> some View {
        if store.activeSession != nil {
            Button {
                WatchHaptics.play(.click)
                onOpenSession()
            } label: {
                Label("Reading now", systemImage: "book.pages.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent)
            .foregroundStyle(WatchTheme.onAccent)
        } else {
            if let tea = store.snapshot.tea {
                Button {
                    WatchHaptics.play(.start)
                    store.startSteep(tea)
                } label: {
                    VStack(spacing: 0) {
                        Label("Steep and read", systemImage: "cup.and.saucer.fill")
                        Text("\(tea.name) · \(WatchTea.steepText(tea.steepSeconds))")
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(WatchTheme.accent)
                .foregroundStyle(WatchTheme.onAccent)
            }
            Button {
                WatchHaptics.play(.start)
                store.start(bookID: book.id)
            } label: {
                Label(store.goalProgress(at: now) >= 1 ? "Read more" : "Start reading", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        }
    }

    /// Today's reading times, the next one marked.
    @ViewBuilder
    private var slots: some View {
        let times = store.snapshot.slots
        if !times.isEmpty {
            let nowMinute = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
            let next = times.first { $0.minuteOfDay >= nowMinute }?.id
            VStack(alignment: .leading, spacing: 3) {
                ForEach(times) { slot in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Circle()
                            .fill(slot.id == next ? WatchTheme.ribbon : WatchTheme.track)
                            .frame(width: 5, height: 5)
                        Text(WatchSlot.timeText(slot.minuteOfDay))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(WatchTheme.paper)
                        Text(slot.label ?? slot.title)
                            .font(.system(size: 11))
                            .foregroundStyle(WatchTheme.inkSecondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 2)
        }
    }

    /// The tea is ready: a cup of reading for the book suggested, timed to the reader's cup length.
    private func startCup() {
        guard let book = store.suggestedBook, let steep = store.steep else { return }
        WatchHaptics.play(.start)
        store.start(bookID: book.id, teaID: steep.tea.id, goalSeconds: Double(store.snapshot.cupMinutes * 60))
    }
}

/// The pot steeping: the cup darkening as the time runs, and the hand-off to reading when it's ready.
struct SteepTimerView: View {
    @Environment(WatchStore.self) private var store
    let steep: SteepTimer
    let now: Date
    let onStart: () -> Void

    var body: some View {
        let remaining = steep.remaining(at: now)
        let ready = steep.isReady(at: now)
        let progress = 1 - remaining / Double(max(1, steep.tea.steepSeconds))
        VStack(spacing: 6) {
            Text(ready ? "\(steep.tea.name) is ready" : "Steeping \(steep.tea.name)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ready ? WatchTheme.accent : WatchTheme.inkSecondary)
            ZStack {
                Circle()
                    .fill(WatchTheme.tea.opacity(0.18 + 0.5 * progress))
                Circle()
                    .strokeBorder(WatchTheme.tea.opacity(0.8), lineWidth: 2)
                Text(ready ? "Ready" : LeafFormat.clock(seconds: remaining.rounded(.up)))
                    .font(WatchTheme.display(ready ? 24 : 30).monospacedDigit())
                    .foregroundStyle(WatchTheme.paper)
                    .contentTransition(.numericText(countsDown: true))
            }
            .frame(width: 92, height: 92)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ready ? "Your tea is ready" : "\(Int(remaining.rounded(.up))) seconds left to steep")
            Button(action: onStart) {
                Label(ready ? "Start the cup" : "Read now", systemImage: "book.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent)
            .foregroundStyle(WatchTheme.onAccent)
            Button("Pour it out") {
                WatchHaptics.play(.retry)
                store.cancelSteep()
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(WatchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: ready) { _, isReady in
            if isReady { WatchHaptics.play(.notification) }
        }
    }
}

/// This week as tea rings on the table: a ring per day sized by the minutes against the goal, a dash on rest days,
/// today underlined, and the streak with the real minutes.
struct WeekPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        let total = Int(snapshot.week.reduce(0) { $0 + $1.minutes })
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(snapshot.streak)")
                    .font(WatchTheme.display(34))
                    .foregroundStyle(WatchTheme.paper)
                Text(snapshot.streak == 1 ? "day in a row" : "days in a row")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 2) {
                ForEach(snapshot.week) { day in
                    VStack(spacing: 4) {
                        WatchTeaRing(day: day)
                            .frame(width: 22, height: 22)
                        Text(LeafFormat.format(day.date, template: "EEEEE"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? WatchTheme.paper : WatchTheme.inkSecondary)
                        Capsule()
                            .fill(Calendar.current.isDateInToday(day.date) ? WatchTheme.ribbon : .clear)
                            .frame(width: 10, height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(dayLabel(day))
                }
            }
            Text("\(LeafFormat.duration(minutes: Double(total))) this week")
                .font(.footnote)
                .foregroundStyle(WatchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .containerBackground(WatchTheme.warm.gradient, for: .tabView)
        .navigationTitle("This week")
    }

    private func dayLabel(_ day: WatchDay) -> String {
        let name = LeafFormat.format(day.date, template: "EEEE")
        if !day.isReadingDay && day.minutes == 0 { return "\(name), rest day" }
        return "\(name), \(Int(day.minutes.rounded())) minutes"
    }
}

/// One day as a tea ring: bigger the longer the read, a drip at the goal, a dash for rest, a faint dot to come.
struct WatchTeaRing: View {
    let day: WatchDay

    var body: some View {
        let share = day.goal > 0 ? day.minutes / Double(day.goal) : 0
        let isFuture = day.date > Date() && !Calendar.current.isDateInToday(day.date)
        ZStack {
            if day.minutes > 0 {
                Circle()
                    .fill(WatchTheme.tea.opacity(0.18))
                    .overlay { Circle().strokeBorder(WatchTheme.tea, lineWidth: share >= 1 ? 2 : 1.2) }
                    .scaleEffect(0.4 + 0.6 * min(1, share))
            } else if !day.isReadingDay {
                Capsule().fill(WatchTheme.track).frame(width: 8, height: 2)
            } else {
                Circle().fill(WatchTheme.track.opacity(isFuture ? 0.6 : 1)).frame(width: 3, height: 3)
            }
        }
    }
}

/// Reading and what's next: start a book, mark it finished, or set it aside.
struct ShelfPage: View {
    @Environment(WatchStore.self) private var store
    var onStart: () -> Void

    var body: some View {
        List {
            if store.reading.isEmpty && store.snapshot.queue.isEmpty {
                Text("Nothing on your shelves yet.")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.inkSecondary)
            }
            if !store.reading.isEmpty {
                Section("Reading") {
                    ForEach(store.reading) { book in
                        NavigationLink(value: WatchRoute.shelfBook(bookID: book.id)) {
                            WatchBookRow(book: book)
                        }
                    }
                }
            }
            if !store.snapshot.queue.isEmpty {
                Section("Up next") {
                    ForEach(store.snapshot.queue.prefix(4)) { book in
                        NavigationLink(value: WatchRoute.shelfBook(bookID: book.id)) {
                            WatchBookRow(book: book)
                        }
                    }
                }
            }
        }
        .containerBackground(WatchTheme.accentDeep.opacity(0.5).gradient, for: .tabView)
        .navigationTitle("Shelf")
    }
}

struct WatchBookRow: View {
    let book: WatchBook

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(WatchTheme.cover(for: book.paletteSeed).gradient)
                .frame(width: 22, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(.body, design: .serif))
                    .lineLimit(2)
                ProgressLine(progress: book.progress)
                Group {
                    if let finish = book.finish {
                        Text("Done \(LeafFormat.relativeDay(finish))")
                    } else {
                        Text("p. \(book.currentPage) of \(book.pages)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What a book on the shelf can do from the wrist.
struct ShelfBookActions: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let book: WatchBook
    let isReading: Bool
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(book.title)
                    .font(.system(.headline, design: .serif))
                    .multilineTextAlignment(.center)
                Text(book.author)
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.inkSecondary)
                Button {
                    WatchHaptics.play(.start)
                    if !isReading { store.moveBook(book.id, to: .reading) }
                    store.start(bookID: book.id)
                    onStart()
                } label: {
                    Label("Start reading", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(WatchTheme.accent)
                .foregroundStyle(WatchTheme.onAccent)
                .disabled(store.activeSession != nil)
                if store.activeSession?.bookID == book.id {
                    // Finishing or setting aside would drop the minutes being timed; end the session first.
                    Text("Reading now. End the session to finish it or set it aside.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WatchTheme.inkSecondary)
                } else if isReading {
                    Button {
                        WatchHaptics.play(.success)
                        store.moveBook(book.id, to: .finished)
                        dismiss()
                    } label: {
                        Label("Mark finished", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button {
                        WatchHaptics.play(.click)
                        store.moveBook(book.id, to: .paused)
                        dismiss()
                    } label: {
                        Label("Set aside", systemImage: "pause").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

struct WatchPlaceholder: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(WatchTheme.accent)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

extension WatchTea {
    /// "4 min", "2:30".
    static func steepText(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension WatchSlot {
    /// "9:00 PM" or "21:00", by the watch's locale.
    static func timeText(_ minuteOfDay: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
