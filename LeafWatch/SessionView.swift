import SwiftUI

/// A live session on the wrist. Mirrors a session started on the phone, too.
struct SessionView: View {
    @Environment(WatchStore.self) private var store
    var onMinimize: () -> Void

    @State private var askingForPage = false
    @State private var celebratedGoal = false

    var body: some View {
        NavigationStack {
            Group {
                if let logged = store.lastLogged, store.activeSession == nil {
                    LoggedView(session: logged)
                } else if let session = store.activeSession {
                    if askingForPage {
                        PageEntryView(session: session, onBack: { askingForPage = false })
                    } else {
                        timer(for: session)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .onAppear {
            if LaunchScreen.current == "pages" { askingForPage = true }
            celebratedGoal = store.goalProgress(at: Date()) >= 1
        }
    }

    private func timer(for session: ActiveSession) -> some View {
        let book = store.snapshot.book(session.bookID)
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = store.goalProgress(at: context.date)
            VStack(spacing: 6) {
                ZStack {
                    GoalRing(progress: progress, lineWidth: 8)
                    VStack(spacing: 0) {
                        Text(LeafFormat.clock(seconds: session.elapsed(at: context.date)))
                            .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(session.isPaused ? WatchTheme.inkSecondary : WatchTheme.paper)
                            .contentTransition(.numericText())
                        Text(session.isPaused ? "paused" : (progress >= 1 ? "goal met" : "reading"))
                            .font(.system(size: 11))
                            .foregroundStyle(progress >= 1 ? WatchTheme.accent : WatchTheme.inkSecondary)
                    }
                }
                .frame(width: 104, height: 104)
                .onChange(of: progress >= 1) { _, reached in
                    if reached && !celebratedGoal {
                        celebratedGoal = true
                        WatchHaptics.play(.success)
                    }
                }

                if let book {
                    Text(book.title)
                        .font(.system(.footnote, design: .serif))
                        .lineLimit(1)
                        .foregroundStyle(WatchTheme.inkSecondary)
                }

                HStack(spacing: 8) {
                    Button {
                        WatchHaptics.play(.click)
                        session.isPaused ? store.resume() : store.pause()
                    } label: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(session.isPaused ? "Resume" : "Pause")

                    Button {
                        WatchHaptics.play(.stop)
                        askingForPage = true
                    } label: {
                        Text("End").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(WatchTheme.accent)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onMinimize()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Minimize")
            }
        }
    }
}

/// Turn the Digital Crown to the page you reached. Starts at a guess from your pace.
struct PageEntryView: View {
    @Environment(WatchStore.self) private var store
    let session: ActiveSession
    var onBack: () -> Void

    @State private var page: Double = 0
    @State private var lastWhole = 0

    var body: some View {
        let pages = store.snapshot.book(session.bookID)?.pages ?? max(session.startPage + 1, 1)
        VStack(spacing: 4) {
            Text("Which page?")
                .font(.footnote)
                .foregroundStyle(WatchTheme.inkSecondary)
            Text("\(Int(page))")
                .font(WatchTheme.display(48))
                .foregroundStyle(WatchTheme.paper)
                .contentTransition(.numericText())
                .focusable()
                .digitalCrownRotation($page, from: Double(session.startPage), through: Double(pages), by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("Page \(Int(page)) of \(pages)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: page = min(Double(pages), page + 1)
                    case .decrement: page = max(Double(session.startPage), page - 1)
                    @unknown default: break
                    }
                }
            Text(Int(page) >= pages ? "The end!" : "of \(pages) · +\(max(0, Int(page) - session.startPage)) pages")
                .font(.system(size: 11))
                .foregroundStyle(Int(page) >= pages ? WatchTheme.accent : WatchTheme.inkSecondary)

            Button {
                WatchHaptics.play(Int(page) >= pages ? .success : .directionUp)
                store.finish(at: Int(page))
            } label: {
                Text(Int(page) >= pages ? "Finish book" : "Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent)
        }
        .onAppear {
            page = Double(store.estimatedPage(for: session))
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("Back to timer")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    WatchHaptics.play(.retry)
                    store.cancel()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Discard session")
            }
        }
    }
}

/// A short wrap-up after logging.
struct LoggedView: View {
    @Environment(WatchStore.self) private var store
    let session: ReadingSession

    var body: some View {
        let book = store.snapshot.book(session.bookID)
        let finished = book.map { session.toPage >= $0.pages } ?? false
        VStack(spacing: 6) {
            Image(systemName: finished ? "book.closed.fill" : "leaf.fill")
                .font(.system(size: 28))
                .foregroundStyle(WatchTheme.accent)
                .symbolEffect(.bounce, value: session.id)
            Text(finished ? "Finished!" : "\(LeafFormat.duration(minutes: session.minutes)) read")
                .font(WatchTheme.display(24))
                .foregroundStyle(WatchTheme.paper)
            Text(finished ? (book?.title ?? "") : "\(session.pagesRead) pages · now on p. \(session.toPage)")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSecondary)
            Button("Done") { store.lastLogged = nil }
                .buttonStyle(.glass)
        }
    }
}
