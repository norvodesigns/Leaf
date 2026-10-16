import SwiftUI

/// The first page: today's ring, what to read, and one big button.
struct TodayPage: View {
    @Environment(WatchStore.self) private var store
    var onOpenSession: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .containerBackground(WatchTheme.accentDeep.gradient, for: .tabView)
        .navigationTitle("Leaf")
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let snapshot = store.snapshot
        if !snapshot.hasOnboarded && snapshot.reading.isEmpty {
            placeholder(symbol: "iphone", text: "Open Leaf on your iPhone to set up your plan.")
        } else if let book = store.suggestedBook {
            VStack(spacing: 6) {
                ZStack {
                    GoalRing(progress: store.goalProgress(at: now))
                    VStack(spacing: -2) {
                        let left = max(0, Double(snapshot.dailyMinutes) - store.minutesToday(at: now))
                        if left < 0.5 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(WatchTheme.accent)
                            Text("done").font(.footnote).foregroundStyle(WatchTheme.inkSecondary)
                        } else {
                            Text("\(Int(left.rounded(.up)))")
                                .font(WatchTheme.display(30))
                                .foregroundStyle(WatchTheme.paper)
                                .contentTransition(.numericText())
                            Text("min left").font(.system(size: 11)).foregroundStyle(WatchTheme.inkSecondary)
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Today's goal, \(Int((store.goalProgress(at: now) * 100).rounded())) percent")

                VStack(spacing: 1) {
                    Text(book.title)
                        .font(.system(.headline, design: .serif))
                        .lineLimit(1)
                        .foregroundStyle(WatchTheme.paper)
                    if let assignment = store.assignment(for: book.id) {
                        Text(LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage))
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.inkSecondary)
                    } else {
                        Text("p. \(book.currentPage) of \(book.pages)")
                            .font(.footnote)
                            .foregroundStyle(WatchTheme.inkSecondary)
                    }
                }

                if store.activeSession != nil {
                    Button {
                        WatchHaptics.play(.click)
                        onOpenSession()
                    } label: {
                        Label("Reading now", systemImage: "book.pages.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(WatchTheme.accent)
                } else {
                    Button {
                        WatchHaptics.play(.start)
                        store.start(bookID: book.id)
                    } label: {
                        Label(store.goalProgress(at: now) >= 1 ? "Read more" : "Start reading", systemImage: "play.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(WatchTheme.accent)
                }
            }
        } else {
            placeholder(symbol: "books.vertical", text: "Add a book in Leaf on your iPhone and it'll appear here.")
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(WatchTheme.accent)
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSecondary)
        }
    }
}

/// This week at a glance: minutes per day against the goal, and the streak.
struct WeekPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let snapshot = store.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(snapshot.streak)")
                    .font(WatchTheme.display(34))
                    .foregroundStyle(WatchTheme.paper)
                Text(snapshot.streak == 1 ? "day streak" : "day streak")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.inkSecondary)
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(snapshot.week) { day in
                    let fraction = day.goal > 0 ? min(1, day.minutes / Double(day.goal)) : 0
                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(WatchTheme.track).frame(height: 54)
                            Capsule()
                                .fill(fraction >= 1 ? WatchTheme.accent : WatchTheme.accent.opacity(0.55))
                                .frame(height: max(day.minutes > 0 ? 6 : 0, 54 * fraction))
                        }
                        .frame(width: 12)
                        Text(LeafFormat.format(day.date, template: "EEEEE"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? WatchTheme.paper : WatchTheme.inkSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(LeafFormat.format(day.date, template: "EEEE")), \(Int(day.minutes)) minutes")
                }
            }
            Text("\(Int(snapshot.week.reduce(0) { $0 + $1.minutes })) min this week")
                .font(.footnote)
                .foregroundStyle(WatchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .containerBackground(WatchTheme.accentDeep.opacity(0.7).gradient, for: .tabView)
        .navigationTitle("This week")
    }
}

/// Everything on the Reading shelf. Tap one to start a session.
struct BooksPage: View {
    @Environment(WatchStore.self) private var store
    var onStart: () -> Void

    var body: some View {
        List {
            if store.reading.isEmpty {
                Text("Nothing on your Reading shelf yet.")
                    .font(.footnote)
                    .foregroundStyle(WatchTheme.inkSecondary)
            }
            ForEach(store.reading) { book in
                Button {
                    guard store.activeSession == nil else { return onStart() }
                    WatchHaptics.play(.start)
                    store.start(bookID: book.id)
                    onStart()
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(WatchTheme.cover(for: book.paletteSeed).gradient)
                            .frame(width: 22, height: 32)
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
                .accessibilityHint("Starts a reading session")
            }
        }
        .containerBackground(WatchTheme.accentDeep.opacity(0.5).gradient, for: .tabView)
        .navigationTitle("Reading")
    }
}
