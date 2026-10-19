import SwiftUI

// The watch's quieter pages (UI-6): logging without the timer, "Where was I?", the forecast, and adding by voice.
// The crown screens are pushed views, not pages, so turning the crown changes a number and never the page.

/// Routes pushed from the pages onto the root stack.
enum WatchRoute: Hashable {
    case quickLog(bookID: String)
    case whereWasI(bookID: String)
    case shelfBook(bookID: String)
}

// MARK: - Log

/// "Read without the timer" and "Where was I?" for each book you're reading.
struct LogPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if store.reading.isEmpty {
                    WatchPlaceholder(symbol: "book", text: "Start a book on your iPhone and it shows up here.")
                } else {
                    ForEach(store.reading.prefix(3)) { book in
                        VStack(alignment: .leading, spacing: 6) {
                            WatchBookRow(book: book)
                            HStack(spacing: 6) {
                                NavigationLink(value: WatchRoute.quickLog(bookID: book.id)) {
                                    Label("Log", systemImage: "plus")
                                        .frame(maxWidth: .infinity)
                                }
                                .accessibilityLabel("Log a read of \(book.title)")
                                NavigationLink(value: WatchRoute.whereWasI(bookID: book.id)) {
                                    Label("Page", systemImage: "bookmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .accessibilityLabel("Where was I in \(book.title)")
                            }
                            .font(.footnote)
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(WatchTheme.accentDeep.opacity(0.7).gradient, for: .tabView)
        .navigationTitle("Log")
    }
}

/// "Read without the timer": the crown sets the minutes, then the page, which starts at a guess from your pace.
struct QuickLogView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let book: WatchBook

    private enum Field { case minutes, page }

    @FocusState private var focus: Field?
    @State private var minutes: Double = 15
    @State private var page: Double = 0
    /// Once the page is turned by hand, the minutes stop moving it.
    @State private var pageTouched = false

    var body: some View {
        VStack(spacing: 6) {
            Text(book.title)
                .font(.system(.footnote, design: .serif))
                .lineLimit(1)
                .foregroundStyle(WatchTheme.inkSecondary)
            HStack(spacing: 6) {
                dial(value: Int(minutes), unit: "min", field: .minutes)
                    .digitalCrownRotation($minutes, from: 1, through: 240, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityLabel("\(Int(minutes)) minutes read")
                    .accessibilityAdjustableAction { direction in
                        minutes = adjust(minutes, direction, lower: 1, upper: 240)
                    }
                dial(value: Int(page), unit: "page", field: .page)
                    .digitalCrownRotation($page, from: Double(book.currentPage), through: Double(book.pages), by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                    .accessibilityLabel("Now on page \(Int(page)) of \(book.pages)")
                    .accessibilityAdjustableAction { direction in
                        pageTouched = true
                        page = adjust(page, direction, lower: Double(book.currentPage), upper: Double(book.pages))
                    }
            }
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.inkSecondary)
                .multilineTextAlignment(.center)
            Button {
                WatchHaptics.play(Int(page) >= book.pages ? .success : .directionUp)
                store.quickLog(bookID: book.id, toPage: Int(page), minutes: minutes)
                dismiss()
            } label: {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent)
        }
        .navigationTitle("Log a read")
        .onAppear {
            minutes = store.assignment(for: book.id).map { max(1, $0.minutes.rounded()) } ?? 15
            page = Double(guessPage(for: minutes))
            focus = .minutes
        }
        .onChange(of: minutes) { _, value in
            if !pageTouched { page = Double(guessPage(for: value)) }
        }
        .onChange(of: page) { _, _ in
            if focus == .page { pageTouched = true }
        }
    }

    private func dial(value: Int, unit: String, field: Field) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(WatchTheme.display(34).monospacedDigit())
                .foregroundStyle(WatchTheme.paper)
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(focus == field ? WatchTheme.accent : WatchTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(WatchTheme.warm, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focus == field ? WatchTheme.accent : .clear, lineWidth: 1.5)
        }
        .focusable()
        .focused($focus, equals: field)
    }

    private var caption: String {
        let pages = max(0, Int(page) - book.currentPage)
        if Int(page) >= book.pages { return "The end!" }
        return "+\(pages) \(pages == 1 ? "page" : "pages") · tap a number"
    }

    /// Where your pace says `minutes` would get you from your current page.
    private func guessPage(for minutes: Double) -> Int {
        let pages = minutes * store.snapshot.wpm / max(book.wordsPerPage, 1)
        return min(book.pages, book.currentPage + Int(pages.rounded()))
    }

    private func adjust(_ value: Double, _ direction: AccessibilityAdjustmentDirection, lower: Double, upper: Double) -> Double {
        switch direction {
        case .increment: return min(upper, value + 1)
        case .decrement: return max(lower, value - 1)
        @unknown default: return value
        }
    }
}

/// "Where was I?": set the page you're really on, without logging time.
struct WhereWasIView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let book: WatchBook

    @State private var page: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            Text("Where are you?")
                .font(.footnote)
                .foregroundStyle(WatchTheme.inkSecondary)
            Text("p. \(Int(page))")
                .font(WatchTheme.display(44).monospacedDigit())
                .foregroundStyle(WatchTheme.paper)
                .contentTransition(.numericText())
                .focusable()
                .digitalCrownRotation($page, from: 0, through: Double(book.pages), by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("Page \(Int(page)) of \(book.pages)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: page = min(Double(book.pages), page + 1)
                    case .decrement: page = max(0, page - 1)
                    @unknown default: break
                    }
                }
            ProgressLine(progress: Double(Int(page)) / Double(max(book.pages, 1)))
                .padding(.horizontal, 12)
            Text(Int(page) == book.currentPage ? "Leaf has you here" : "was p. \(book.currentPage) of \(book.pages)")
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.inkSecondary)
            Button {
                WatchHaptics.play(.click)
                store.setPage(bookID: book.id, page: Int(page))
                dismiss()
            } label: {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent)
            .disabled(Int(page) == book.currentPage)
        }
        .navigationTitle(book.title)
        .onAppear { page = Double(book.currentPage) }
    }
}

// MARK: - Forecast

/// The year as a ring and a sentence, then when each book will likely be done.
struct ForecastPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let year = store.snapshot.yearGoal, year.goal > 0 {
                    HStack(spacing: 10) {
                        ZStack {
                            GoalRing(progress: Double(year.finished) / Double(year.goal), lineWidth: 6)
                            Text("\(year.finished)")
                                .font(WatchTheme.display(20).monospacedDigit())
                                .foregroundStyle(WatchTheme.paper)
                        }
                        .frame(width: 50, height: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(year.finished) of \(year.goal) in \(String(year.year))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WatchTheme.paper)
                            Text(year.sentence)
                                .font(.system(size: 12))
                                .foregroundStyle(WatchTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(year.finished) of \(year.goal) books read in \(String(year.year)). \(year.sentence)")
                }
                if store.snapshot.forecasts.isEmpty {
                    WatchPlaceholder(symbol: "calendar", text: "Forecasts appear once you've read a few times.")
                } else {
                    ForEach(store.snapshot.forecasts) { forecast in
                        forecastRow(forecast)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(WatchTheme.tea.opacity(0.35).gradient, for: .tabView)
        .navigationTitle("Forecast")
    }

    private func forecastRow(_ forecast: WatchForecast) -> some View {
        let book = store.snapshot.book(forecast.bookID)
        return VStack(alignment: .leading, spacing: 3) {
            Text(book?.title ?? "A book")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(WatchTheme.paper)
                .lineLimit(1)
            Text(forecast.sentence)
                .font(.system(size: 12))
                .foregroundStyle(WatchTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
            if let book {
                ProgressLine(progress: book.progress, color: WatchTheme.cover(for: book.paletteSeed).mix(with: WatchTheme.paper, by: 0.35))
            }
        }
        .padding(8)
        .background(WatchTheme.warm, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book?.title ?? "A book"). \(forecast.sentence)")
    }
}

// MARK: - Add

/// Add by voice: a book to the queue (the phone finds it), or a thought or a quote for the book you're reading.
struct AddPage: View {
    @Environment(WatchStore.self) private var store
    @State private var sent: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let sent {
                    Label(sent, systemImage: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(WatchTheme.accent)
                        .transition(.opacity)
                }
                TextFieldLink(prompt: Text("Title or author")) {
                    Label("A book to read", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } onSubmit: { text in
                    store.addBook(query: text)
                    confirm("Sent to your iPhone to find.")
                }
                if let book = store.suggestedBook {
                    Text(book.title)
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(WatchTheme.inkSecondary)
                        .lineLimit(1)
                        .padding(.top, 4)
                    TextFieldLink(prompt: Text("A thought")) {
                        Label("A thought", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } onSubmit: { text in
                        store.addJournal(bookID: book.id, kind: .thought, text: text)
                        confirm("Kept with p. \(book.currentPage).")
                    }
                    TextFieldLink(prompt: Text("A line you loved")) {
                        Label("A quote", systemImage: "quote.opening")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } onSubmit: { text in
                        store.addJournal(bookID: book.id, kind: .quote, text: text)
                        confirm("Kept with p. \(book.currentPage).")
                    }
                }
            }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(WatchTheme.warm.gradient, for: .tabView)
        .navigationTitle("Add")
        .onAppear {
            if LaunchScreen.current == "add.sent" { sent = "Sent to your iPhone to find." }
        }
    }

    private func confirm(_ text: String) {
        WatchHaptics.play(.success)
        withAnimation { sent = text }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if sent == text { sent = nil } }
        }
    }
}

// MARK: - Atmosphere

/// Warm out-of-focus lights drifting behind the session timer, from the same generator as the phone. Still when paused,
/// with Reduce Motion, and gone in Always-On.
struct WatchAtmosphere: View {
    var isPaused: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !isLuminanceReduced {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: isPaused || reduceMotion)) { context in
                Canvas { canvas, size in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let side = min(size.width, size.height)
                    for light in AtmosphereField.bokeh(seed: 11, time: time, count: 7, calm: isPaused ? 0 : 0.7) {
                        let radius = CGFloat(light.radius) * side
                        let rect = CGRect(x: CGFloat(light.x) * size.width - radius, y: CGFloat(light.y) * size.height - radius, width: radius * 2, height: radius * 2)
                        let colour = WatchTheme.tea.mix(with: WatchTheme.ribbon, by: max(0, light.hueOffset) * 0.4)
                        canvas.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(colors: [colour.opacity(light.opacity * 0.55), colour.opacity(0)]),
                                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: radius
                            )
                        )
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}
