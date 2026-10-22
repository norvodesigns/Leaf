import SwiftUI

/// What the Nook's one button does right now.
enum NookAction: Equatable {
    /// "Steep and read": pour, wait for the tea, then read one cup.
    case steep
    case steeping(TeaSteepState)
    case ready(TeaSteepState)
    /// A session is running: return to it.
    case live
    /// Today's minutes are read: "Read a little more".
    case readMore
    /// A rest day: the same ritual, offered quietly.
    case restDay
    /// Nothing to read yet.
    case findBook(firstEver: Bool)
}

/// The things the Nook can ask Today to do.
struct NookActions {
    var steep: () -> Void
    /// Start reading the book on the table (with the steeped tea, if there is one).
    var start: () -> Void
    var startWithoutTea: () -> Void
    var startBook: (String) -> Void
    var pourOut: () -> Void
    var chooseTea: (Tea) -> Void
    var findBook: () -> Void
    var openBook: (Book) -> Void
    var readingTimes: () -> Void
}

/// The Reading Nook, on Canopy (docs/design/REDESIGN.md §4.1): the top of Today, kept from the live app and cleaned up.
/// The greeting set large in
/// Instrument Serif, a still life of the book on the table beside a cup that fills as the day's minutes come in
/// (the real minutes beside it), and one button: "Steep and read". Steeping happens here, before the session, so
/// the session's clock only ever counts reading.
struct TodayNook: View {
    let brief: TodayBrief
    let daypart: Daypart
    let dateline: String
    let issueNumber: Int
    let issueSpoken: String
    /// The tea for this hour (or the one the reader picked), its steep time, and other teas that suit the hour.
    let tea: Tea
    let steepSeconds: Int
    let teaChoices: [Tea]
    let action: NookAction
    /// Books open in Reading, for "read instead" in the button's menu.
    let readingBooks: [LibraryItem]
    let actions: NookActions
    /// How far the scroll view's content starts below the top of the screen (the status bar and the bar with the
    /// gear). The nook's light reaches up behind them, so the top of Today is one scene, not a band of plain paper.
    var topInset: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var typeSize

    private var book: Book? { brief.current?.item.book }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            datelineView
                .inkIn(0)
            greetingView
                .padding(.top, Space.xl)
                .inkIn(1)
            stillLife
                .coachMarkAnchor("today.nook")
                .padding(.top, Space.xxl)
                .inkIn(2)
            controls
                .padding(.top, Space.l)
                .inkIn(3)
        }
        .leafMargins()
        .padding(.top, Space.s)
        .padding(.bottom, Space.l)
        // No lamp glow or bokeh any more: the page is Canopy's clean cream (DESIGN_SYSTEM.md §3).
    }

    // MARK: Dateline and greeting

    private var datelineView: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(dateline)
                    .leafStyle(.eyebrow)
                Spacer(minLength: Space.m)
                Text("No. \(issueNumber)")
                    .leafStyle(.eyebrow)
                    .accessibilityLabel(issueSpoken)
            }
            DoubleRule()
        }
    }

    private var greetingView: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(brief.greeting.headline)
                .leafStyle(.display)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subline = brief.greeting.subline {
                Text(subline)
                    .leafStyle(.pullQuote, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Still life

    /// The cup is full, or a pot is on.
    private var steams: Bool {
        switch action {
        case .steeping, .ready: return true
        default: return brief.goalMinutes > 0 && brief.goalProgress >= 1
        }
    }

    private var cupFill: Double {
        if case .ready = action, brief.goalProgress < 0.15 { return 0.9 }
        return brief.goalProgress
    }

    private var liquor: Color {
        switch action {
        case .steeping(let state), .ready(let state): return CozyColor.liquor(for: state.tea)
        default: return CozyColor.liquor(for: tea)
        }
    }

    private var stillLife: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: Space.l) {
                if let book {
                    Button {
                        actions.openBook(book)
                    } label: {
                        BookCover(book: book, size: typeSize.isAccessibilitySize ? .s : .m, ribbon: !typeSize.isAccessibilitySize, swaysRibbon: true)
                            .todayBookZoomSource(book.id)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens book details")
                }
                TeaCup(fill: cupFill, liquor: liquor, steams: steams, width: typeSize.isAccessibilitySize ? 64 : 88)
                cupCaption
                    .padding(.bottom, Space.m)
                Spacer(minLength: 0)
            }
            .zIndex(1)
            table
        }
    }

    /// A strip of tea-stained table under the cup and the book, full bleed.
    private var table: some View {
        Rectangle()
            .fill(Canopy.separator)
            .frame(height: 1)
        .padding(.horizontal, -Space.margin)
        .accessibilityHidden(true)
    }

    private var cupCaption: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            minutesLineView
                .numericBlur(value: brief.minutesReadToday)
            Text(cupPhrase)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "12" large, "of 25 min" beside it.
    private var minutesLineView: some View {
        let read = Int(brief.minutesReadToday.rounded())
        return HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text("\(read)").canopyText(.stat)
            Text(brief.goalMinutes > 0 ? "of \(brief.goalMinutes) min" : "min today")
                .canopyText(.callout, color: Canopy.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(minutesLine)
    }

    /// "12 of 25 min today"
    private var minutesLine: String {
        let read = Int(brief.minutesReadToday.rounded())
        if brief.goalMinutes > 0 { return "\(read) of \(brief.goalMinutes) min" }
        return "\(read) min today"
    }

    /// The cup in words. The minutes beside it are the real measure.
    private var cupPhrase: String {
        switch action {
        case .steeping(let state): return "\(state.tea.name), steeping"
        case .ready(let state): return "\(state.tea.name), ready"
        default: break
        }
        if brief.mode == .restDay && brief.minutesReadToday < 1 { return "A rest day. No cup needed." }
        let progress = brief.goalProgress
        if brief.goalMinutes > 0 && progress >= 1 { return "A full cup" }
        if brief.minutesReadToday < 1 { return "An empty cup, for now" }
        if progress < 0.34 { return "A few sips in" }
        if progress < 0.67 { return "About half a cup" }
        return "Nearly a full cup"
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch action {
        case .steep:
            steepControls(prominent: true)
        case .restDay:
            steepControls(prominent: false)
        case .steeping(let state):
            steepingControls(state)
        case .ready(let state):
            readyControls(state)
        case .live:
            CanopyHeroButton("Back to your book", systemImage: "book", feel: .resume) {
                actions.start()
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
        case .readMore:
            VStack(alignment: .leading, spacing: Space.s) {
                CanopyGlassButton("Read a little more", systemImage: "book", accent: .forest, feel: nil) {
                    actions.startWithoutTea()
                }
                .sessionZoomSource(ReadingSessionLauncher.heroSource)
                .contextMenu { optionsMenu }
                Text("Today’s reading is done. Anything more is a gift.")
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .findBook(let firstEver):
            CanopyHeroButton(firstEver ? "Find your first book" : "Pick your next book", systemImage: "magnifyingglass", feel: .tap) {
                actions.findBook()
            }
        }
    }

    private var teaChip: some View {
        Menu {
            Section("Teas for this hour") {
                ForEach(teaChoices) { choice in
                    Button {
                        actions.chooseTea(choice)
                    } label: {
                        Label(
                            "\(choice.name) · \(SteepText.duration(seconds: TeaSuggester.steepSeconds(for: choice, strength: CozySettings.teaStrength)))",
                            systemImage: choice.id == tea.id ? "checkmark" : "leaf"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "cup.and.saucer")
                    .foregroundStyle(CanopyAccent.clay.color)
                Text("\(tea.name) · \(SteepText.duration(seconds: steepSeconds)) steep")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Canopy.text)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Canopy.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .canopyGlass()
            .frame(minHeight: Space.hitTarget)
            .contentShape(.rect)
        }
        .accessibilityLabel("Tea: \(tea.name), steeps \(SteepText.spoken(seconds: steepSeconds))")
        .accessibilityHint("Choose another tea")
    }

    /// The tea, what steeping means today, then the two ways in as a pair: "Steep and read" in glass, "Begin
    /// reading" in ink. Side by side when they fit, one above the other when the type is large.
    private func steepControls(prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                teaChip
                ritualCaption
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    steepButton(prominent: prominent)
                    beginButton(prominent: prominent)
                }
                VStack(spacing: Space.s) {
                    steepButton(prominent: prominent)
                    beginButton(prominent: prominent)
                }
            }
            .coachMarkAnchor("today.steep")
        }
    }

    private func steepButton(prominent: Bool) -> some View {
        CanopyGlassButton("Steep and read", systemImage: "cup.and.heat.waves", accent: .clay) {
            actions.steep()
        }
        .sessionZoomSource(ReadingSessionLauncher.heroSource)
        .contextMenu { optionsMenu }
        .accessibilityHint("Steeps your tea first, then starts a cup of reading")
    }

    /// Reading straight away, no tea: the black glass Hero. On a rest day a quiet glass "Read a little" instead, so
    /// nothing pushes. The launcher plays the start haptic.
    @ViewBuilder
    private func beginButton(prominent: Bool) -> some View {
        if prominent {
            CanopyHeroButton("Begin reading", feel: nil) {
                actions.startWithoutTea()
            }
            .accessibilityHint("Starts reading now, without steeping tea")
        } else {
            CanopyGlassButton("Read a little", systemImage: "book", accent: .forest, feel: nil) {
                actions.startWithoutTea()
            }
            .accessibilityHint("Starts reading now, without steeping tea")
        }
    }

    private var ritualCaption: some View {
        Text("Steep \(SteepText.duration(seconds: steepSeconds)), then read a \(brief.cupMinutes)-minute cup.")
            .leafStyle(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func steepingControls(_ state: TeaSteepState) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    CanopyLabel("\(state.tea.name) is steeping", accent: .clay)
                    // The countdown is always sharp (blur is a moment, never a state).
                    Text(timerInterval: state.startedAt...state.readyAt, countsDown: true)
                        .font(CanopyType.stat.font.monospacedDigit())
                        .foregroundStyle(Canopy.text)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                Spacer(minLength: 0)
            }
            Text("Find your page and settle in. It’s ready at \(LeafFormat.format(state.readyAt, template: "jmm")).")
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            CanopyHeroButton("Start reading now", feel: nil) {
                actions.start()
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
            TextButton("Pour it out", color: .inkSecondary) {
                actions.pourOut()
            }
        }
    }

    private func readyControls(_ state: TeaSteepState) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            CanopyLabel("Your \(state.tea.name) is ready", accent: .clay)
                .canopyFocusInTransition()
            Text("One cup is \(brief.cupMinutes) minutes. Leaf counts it down for you.")
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            CanopyHeroButton("Begin reading", feel: nil) {
                actions.start()
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
            TextButton("Pour it out", color: .inkSecondary) {
                actions.pourOut()
            }
        }
    }

    @ViewBuilder
    private var optionsMenu: some View {
        if readingBooks.count > 1 {
            Section("Read instead") {
                ForEach(readingBooks) { item in
                    Button(item.book.title, systemImage: "book") {
                        actions.startBook(item.id)
                    }
                }
            }
        }
        Button("Begin reading without tea", systemImage: "book") {
            actions.startWithoutTea()
        }
        Button("Reading times", systemImage: "clock") {
            actions.readingTimes()
        }
    }
}
