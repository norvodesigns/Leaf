import SwiftUI

// MARK: - State

/// What the accessory tells the reader right now (DESIGN.md §5). It is always present, so it changes
/// state instead of disappearing.
private enum AccessoryState {
    case live(ActiveSession, Book)
    case paused(ActiveSession, Book)
    case ready(minutes: Int, book: Book, assignment: Assignment)
    case done(minutes: Int, streak: Int)
    case rest(Book?)
    case empty
}

@MainActor
private func accessoryState(for store: LibraryStore) -> AccessoryState {
    if let active = store.activeSession, let book = store.item(active.bookID)?.book {
        return active.isPaused ? .paused(active, book) : .live(active, book)
    }
    if store.reading.isEmpty && store.toRead.isEmpty { return .empty }
    if store.goalMetToday {
        return .done(minutes: Int(store.minutesReadToday.rounded()), streak: store.streak)
    }
    let today = store.todayAssignments
    if let first = today.first {
        let total = today.reduce(0.0) { $0 + $1.assignment.minutes }
        return .ready(minutes: max(1, Int(total.rounded())), book: first.item.book, assignment: first.assignment)
    }
    return .rest(store.nextBook?.book)
}

// MARK: - Row

/// Everything one state of the accessory shows.
private struct AccessoryModel {
    enum Leading {
        case cover(Book)
        case ring(Double)
        case done
        case symbol(String)
    }

    var leading: Leading
    var showsLiveDot = false
    var line1: Text
    var line1Color: Color = Color.ink
    var line2: Text?
    /// Drives the `numericText` roll of the live clock.
    var numeric: Double = 0
    /// The trailing 36 pt symbol button.
    var symbol: String
    var symbolLabel: String
    /// What the tap target reads as, e.g. "Reading, 12:04, The Hobbit".
    var spoken: String
    var bodyHint: String
}

/// The accessory's layout: a leading mark, two lines, and a trailing plain symbol button. In the
/// inline placement it keeps the symbol and line 1 only. Controls here are plain (no nested glass).
private struct AccessoryRow: View {
    let model: AccessoryModel
    let isInline: Bool
    let onBody: () -> Void
    let onSymbol: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.m) {
            Button(action: onBody) {
                HStack(spacing: Space.m) {
                    if !isInline {
                        leading
                    }
                    texts
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.spoken)
            .accessibilityHint(model.bodyHint)

            Button {
                onSymbol()
            } label: {
                Image(systemName: model.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    // A 44 pt hit area without growing the bar.
                    .padding(4)
                    .contentShape(.rect)
                    .padding(-4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.symbolLabel)
        }
        .padding(.horizontal, 16)
        .sessionZoomSource(ReadingSessionLauncher.accessorySource)
    }

    @ViewBuilder
    private var leading: some View {
        switch model.leading {
        case .cover(let book):
            BookCover(book: book, size: .xs)
        case .ring(let progress):
            ProgressRing.accessory(progress: progress)
                .frame(width: 24, height: 36)
        case .done:
            ProgressRing.accessory(progress: 1)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                }
                .frame(width: 24, height: 36)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 20))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 24, height: 36)
                .accessibilityHidden(true)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                if model.showsLiveDot {
                    Circle()
                        .fill(Color.ribbon)
                        .frame(width: 6, height: 6)
                        .breathing(true)
                        .accessibilityHidden(true)
                }
                model.line1
                    .leafStyle(.ui, color: model.line1Color)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: model.numeric))
                    .animation(reduceMotion ? nil : Motion.paper, value: model.numeric)
            }
            if !isInline, let line2 = model.line2 {
                line2
                    .leafStyle(.caption)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Accessory

/// The tab bar's bottom accessory (`.tabViewBottomAccessory`): the day's one-line status and its one
/// action. Six states (ready, live, paused, done, rest, empty), expanded or inline.
struct SessionAccessory: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    private var isInline: Bool { placement == .inline }

    var body: some View {
        switch accessoryState(for: store) {
        case .live(let session, let book):
            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                AccessoryRow(
                    model: liveModel(session: session, book: book, at: context.date),
                    isInline: isInline,
                    onBody: openSession,
                    onSymbol: pause
                )
            }
        case .paused(let session, let book):
            AccessoryRow(
                model: pausedModel(session: session, book: book),
                isInline: isInline,
                onBody: openSession,
                onSymbol: resume
            )
        case .ready(let minutes, let book, let assignment):
            AccessoryRow(
                model: readyModel(minutes: minutes, book: book, assignment: assignment),
                isInline: isInline,
                onBody: { startReading(bookID: book.id) },
                onSymbol: { startReading(bookID: book.id) }
            )
        case .done(let minutes, let streak):
            AccessoryRow(
                model: doneModel(minutes: minutes, streak: streak),
                isInline: isInline,
                onBody: { startReading(bookID: nil) },
                onSymbol: { startReading(bookID: nil) }
            )
        case .rest(let book):
            AccessoryRow(
                model: restModel(book: book),
                isInline: isInline,
                onBody: { startReading(bookID: nil) },
                onSymbol: { startReading(bookID: nil) }
            )
        case .empty:
            AccessoryRow(
                model: emptyModel,
                isInline: isInline,
                onBody: findBook,
                onSymbol: findBook
            )
        }
    }

    // MARK: Models

    private func liveModel(session: ActiveSession, book: Book, at date: Date) -> AccessoryModel {
        let clock = SessionClock(session: session, store: store, at: date)
        let time = LeafFormat.clock(seconds: clock.elapsed)
        let onWatch = session.origin == .watch
        let line2: Text = onWatch
            ? Text("\(Text(book.title).italic()) · on Apple Watch \(Image(systemName: "applewatch"))")
            : Text(book.title).italic()
        return AccessoryModel(
            leading: .ring(clock.ringProgress),
            showsLiveDot: true,
            line1: Text(verbatim: "Reading · \(time)"),
            line2: line2,
            numeric: clock.elapsed.rounded(.down),
            symbol: "pause.fill",
            symbolLabel: "Pause",
            spoken: "Reading \(book.title), \(spokenTime(clock.elapsed))\(onWatch ? ", on Apple Watch" : "")",
            bodyHint: "Opens the reading session"
        )
    }

    private func pausedModel(session: ActiveSession, book: Book) -> AccessoryModel {
        let elapsed = session.elapsed()
        return AccessoryModel(
            leading: .cover(book),
            line1: Text(verbatim: "Paused · \(LeafFormat.clock(seconds: elapsed))"),
            line1Color: Color.inkSecondary,
            line2: Text(book.title).italic(),
            numeric: elapsed.rounded(.down),
            symbol: "play.fill",
            symbolLabel: "Resume",
            spoken: "Paused, \(book.title), \(spokenTime(elapsed))",
            bodyHint: "Opens the reading session"
        )
    }

    private func readyModel(minutes: Int, book: Book, assignment: Assignment) -> AccessoryModel {
        AccessoryModel(
            leading: .cover(book),
            line1: Text("\(minutes) min · \(Text(book.title).italic())"),
            line2: Text(LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage)),
            numeric: Double(minutes),
            symbol: "play.fill",
            symbolLabel: "Start reading",
            spoken: "\(minutes) minutes of \(book.title), \(LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage))",
            bodyHint: "Starts a reading session"
        )
    }

    private func doneModel(minutes: Int, streak: Int) -> AccessoryModel {
        let line2 = streak >= 3 ? "\(streak) reading days in a row" : "Anything more is a gift."
        return AccessoryModel(
            leading: .done,
            line1: Text(verbatim: "Done for today · \(minutes) min"),
            line2: Text(verbatim: line2),
            numeric: Double(minutes),
            symbol: "play.fill",
            symbolLabel: "Read a little more",
            spoken: "Done for today, \(minutes) minutes. \(line2)",
            bodyHint: "Starts another reading session"
        )
    }

    private func restModel(book: Book?) -> AccessoryModel {
        let leading: AccessoryModel.Leading
        if let book {
            leading = .cover(book)
        } else {
            leading = .symbol("moon.zzz")
        }
        return AccessoryModel(
            leading: leading,
            line1: Text("A rest day"),
            line2: Text("Read anyway?"),
            symbol: "play.fill",
            symbolLabel: "Read anyway",
            spoken: "A rest day. Read anyway?",
            bodyHint: "Starts a reading session"
        )
    }

    private var emptyModel: AccessoryModel {
        // "First" only for someone who has never read with Leaf; between books it's the next one.
        let firstEver = store.data.items.isEmpty && store.data.sessions.isEmpty
        let line = firstEver ? "Find your first book" : "Find your next book"
        return AccessoryModel(
            leading: .symbol("books.vertical"),
            line1: Text(line),
            line2: nil,
            symbol: "magnifyingglass",
            symbolLabel: "Search for a book",
            spoken: line,
            bodyHint: "Opens Search"
        )
    }

    // MARK: Actions

    private func openSession() {
        Haptics.shared.tap()
        router.presentSession(from: ReadingSessionLauncher.accessorySource)
    }

    private func pause() {
        Haptics.shared.soft(0.6)
        store.pauseSession()
    }

    private func resume() {
        Haptics.shared.tap()
        store.resumeSession()
    }

    private func startReading(bookID: String?) {
        Haptics.shared.press()
        ReadingSessionLauncher.start(bookID: bookID, store: store, router: router, from: ReadingSessionLauncher.accessorySource)
    }

    private func findBook() {
        Haptics.shared.selection()
        router.tab = .search
    }

    private func spokenTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let rest = total % 60
        if minutes == 0 { return "\(rest) seconds" }
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes") \(rest) seconds"
    }
}

// MARK: - Previews

@MainActor
private func accessoryPreviewStore(session: Bool, paused: Bool = false) -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    if session {
        store.startSession(bookID: DemoData.hobbit.id, startedAt: Date().addingTimeInterval(-(12 * 60 + 4)))
        if paused { store.pauseSession() }
    }
    return store
}

private struct AccessoryPreviewHost: View {
    var body: some View {
        SessionAccessory()
            .frame(height: 52)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, Space.margin)
    }
}

#Preview("Accessory · ready") {
    AccessoryPreviewHost()
        .frame(maxHeight: .infinity)
        .paperBackground()
        .environment(accessoryPreviewStore(session: false))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Accessory · live") {
    AccessoryPreviewHost()
        .frame(maxHeight: .infinity)
        .paperBackground()
        .environment(accessoryPreviewStore(session: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Accessory · paused") {
    AccessoryPreviewHost()
        .frame(maxHeight: .infinity)
        .paperBackground()
        .environment(accessoryPreviewStore(session: true, paused: true))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
