import SwiftUI

// MARK: - Card

/// One of Today's cards, on Canopy: a cream glass card with a green section label and an optional quiet action on
/// the right ("Edit ›").
struct TodayCard<Content: View>: View {
    let eyebrow: String
    var actionTitle: String?
    var action: (() -> Void)?
    let content: Content

    init(_ eyebrow: String, actionTitle: String? = nil, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.eyebrow = eyebrow
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CanopyLabel(eyebrow, linkTitle: actionTitle, link: action)
            content
        }
        .canopyCard()
    }
}

// MARK: - Page chip

/// "p. 142 ✎": where the reader is, as a chip they can tap to change it. Reads "Where are you?" in `ribbon`
/// when Leaf doesn't know yet, and a percentage for books read on an e-reader.
struct PageChip: View {
    let item: LibraryItem
    var needsPosition: Bool = false
    let action: () -> Void

    private var text: String {
        if needsPosition { return "Where are you?" }
        if item.progressMode == .percent { return "\(item.percent)%" }
        return item.currentPage > 0 ? "p. \(item.currentPage)" : "Page one"
    }

    var body: some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Chip(text, systemImage: "pencil", tone: needsPosition ? .ribbon : .neutral)
                .frame(minHeight: Space.hitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(needsPosition ? "Where are you in \(item.book.title)?" : "On \(text) of \(item.book.title)")
        .accessibilityHint("Change where you are")
    }
}

// MARK: - Left off

/// Where the reader left off: the book, the page as a chip, today's span on the page bar and what it asks for.
struct LeftOffCard: View {
    let today: TodayBook
    let mode: TodayMode
    let minutesToGoal: Int
    let minutesReadToday: Double
    let finish: Date?
    let calendar: Calendar
    let onPosition: () -> Void
    let onOpen: () -> Void

    private var item: LibraryItem { today.item }
    private var assignment: Assignment? { today.assignment }
    private var finishesTonight: Bool { assignment?.finishesBook ?? false }

    private var eyebrow: String {
        if today.needsPosition { return "On your desk" }
        if finishesTonight { return "The last pages" }
        return item.currentPage > 0 ? "Where you left off" : "Up first"
    }

    var body: some View {
        TodayCard(eyebrow) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.m) {
                    Button(action: onOpen) {
                        BookCover(book: item.book, size: .s)
                            .todayBookZoomSource(item.id)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(item.book.title) by \(item.book.author)")
                    .accessibilityHint("Opens book details")
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(item.book.title)
                            .leafStyle(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.book.author)
                            .leafStyle(.author)
                        PageChip(item: item, needsPosition: today.needsPosition, action: onPosition)
                            .padding(.top, -Space.xs)
                    }
                    Spacer(minLength: 0)
                }
                if !today.needsPosition {
                    PageSpanBar(current: item.currentPage, todayTo: assignment?.toPage ?? item.currentPage, total: item.book.pages)
                }
                Text(line)
                    .leafStyle(finishesTonight || today.needsPosition ? .pullQuote : .body)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption)
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The sentence for today.
    private var line: String {
        if today.needsPosition {
            return "Tell Leaf your page and the plan will follow."
        }
        switch mode {
        case .goalMet:
            return "Today’s pages are done. Anything more is a gift."
        case .restDay:
            return "No pages today. Your bookmark will keep."
        default:
            break
        }
        guard let assignment else {
            return "Nothing planned for it today. Read anyway if you like."
        }
        let pages = max(0, assignment.toPage - assignment.fromPage + 1)
        if assignment.finishesBook {
            return "The last \(pages == 1 ? "page" : "\(pages) pages"). You could finish tonight."
        }
        let range = LeafFormat.pages(from: assignment.fromPage, to: assignment.toPage)
        if minutesReadToday >= 1, minutesToGoal > 0 {
            return "About \(range) today, \(minutesToGoal) min to stay on plan."
        }
        return "About \(range) today, \(max(1, Int(assignment.minutes.rounded()))) min."
    }

    /// "p. 142 of 310 · done by Sun 26 Oct"
    private var caption: String? {
        guard !today.needsPosition else { return nil }
        var parts = ["\(item.currentPage) of \(LeafFormat.number(item.book.pages)) pages"]
        if let finish, !finishesTonight {
            parts.append("done by \(LeafFormat.format(finish, template: "EEEdMMM", calendar: calendar))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Also open

/// Other books open in Reading, each with its page chip.
struct DeskCard: View {
    let items: [LibraryItem]
    let onPosition: (LibraryItem) -> Void
    let onOpen: (LibraryItem) -> Void

    var body: some View {
        TodayCard("Also on your desk") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: Space.m) {
                        Button {
                            onOpen(item)
                        } label: {
                            HStack(spacing: Space.m) {
                                BookCover(book: item.book, size: .xs)
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text(item.book.title)
                                        .leafStyle(.headline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    ProgressBar(progress: item.progress)
                                        .frame(maxWidth: 120)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("\(item.book.title), \(item.percent) percent read")
                        .accessibilityHint("Opens book details")
                        PageChip(item: item, needsPosition: !item.positionConfirmed) {
                            onPosition(item)
                        }
                    }
                    .padding(.vertical, Space.xs)
                    if item.id != items.last?.id {
                        Hairline()
                    }
                }
            }
        }
    }
}

// MARK: - Forecast

struct ForecastCard: View {
    let sentence: String
    let onPlan: () -> Void

    var body: some View {
        TodayCard("Forecast", actionTitle: "Plan", action: onPlan) {
            Text(sentence)
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reading times

/// Today's reading times: when, which book, which pages. Past times are quiet; the next one wears a `ribbon` dot.
struct ReadingTimesCard: View {
    let plans: [SlotPlan]
    /// Times set for today that have nothing planned in them (a goal already met, say).
    let quietSlots: [ReadingSlot]
    let hasAnySlots: Bool
    let nextSlotID: UUID?
    let now: Date
    let calendar: Calendar
    let title: (String) -> String?
    let onEdit: () -> Void
    let onStart: (String) -> Void

    private var minuteNow: Int {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var body: some View {
        TodayCard("Reading times", actionTitle: hasAnySlots ? "Edit" : nil, action: hasAnySlots ? onEdit : nil) {
            if !hasAnySlots {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Set a time, or a few, and Leaf will share the day’s pages between them. A book can have its own time.")
                        .leafStyle(.body, color: .inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextButton("Add a reading time", color: .accent) {
                        Haptics.shared.tap()
                        onEdit()
                    }
                }
            } else if plans.isEmpty && quietSlots.isEmpty {
                Text("No reading times today.")
                    .leafStyle(.body, color: .inkSecondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(plans) { plan in
                        row(slot: plan.slot, plan: plan)
                        if plan.id != plans.last?.id || !quietSlots.isEmpty {
                            Hairline()
                        }
                    }
                    ForEach(quietSlots) { slot in
                        row(slot: slot, plan: nil)
                        if slot.id != quietSlots.last?.id {
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private func row(slot: ReadingSlot, plan: SlotPlan?) -> some View {
        let isPast = slot.minuteOfDay < minuteNow && slot.id != nextSlotID
        let isNext = slot.id == nextSlotID
        let bookID = plan?.parts.first?.bookID
        return HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(LeafFormat.time(hour: slot.hour, minute: slot.minute, calendar: calendar))
                    .leafStyle(.data, color: isPast ? Color.inkTertiary : CanopyAccent.dusk.color)
                    .frame(minWidth: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.s) {
                        Text(slot.label ?? defaultLabel(for: slot))
                            .leafStyle(.ui, color: isPast ? Color.inkSecondary : Color.ink)
                        if isNext {
                            Circle()
                                .fill(CanopyAccent.dusk.color)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(detail(plan))
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(slot: slot, plan: plan, isNext: isNext, isPast: isPast))
            Spacer(minLength: 0)
            if let bookID, !isPast {
                Button {
                    Haptics.shared.press()
                    onStart(bookID)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Start reading \(title(bookID) ?? "now")")
            }
        }
        .padding(.vertical, Space.s)
    }

    private func detail(_ plan: SlotPlan?) -> String {
        guard let plan, !plan.parts.isEmpty else { return "Nothing planned. Read if you like." }
        return plan.parts.map { part in
            let name = title(part.bookID) ?? "Your book"
            let minutes = max(1, Int(part.minutes.rounded()))
            return "\(name) · \(LeafFormat.pages(from: part.fromPage, to: part.toPage)) · \(minutes) min"
        }
        .joined(separator: "\n")
    }

    private func spoken(slot: ReadingSlot, plan: SlotPlan?, isNext: Bool, isPast: Bool) -> String {
        let time = LeafFormat.time(hour: slot.hour, minute: slot.minute, calendar: calendar)
        let name = slot.label ?? defaultLabel(for: slot)
        let state = isNext ? ", next" : (isPast ? ", earlier today" : "")
        return "\(time), \(name)\(state). \(detail(plan).replacingOccurrences(of: "\n", with: ". "))"
    }

    private func defaultLabel(for slot: ReadingSlot) -> String {
        ReadingSlotText.defaultLabel(hour: slot.hour)
    }
}

// MARK: - A pick

/// One suggestion for later, with the reason in plain words.
struct PickCard: View {
    let pick: Recommendation
    let wpm: Double
    let onKeep: () -> Void
    let onPass: () -> Void
    let onOpen: () -> Void

    var body: some View {
        TodayCard("Something for later") {
            VStack(alignment: .leading, spacing: Space.m) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: Space.m) {
                        BookCover(book: pick.book, size: .s)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(pick.book.title)
                                .leafStyle(.headline)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(pick.book.author)
                                .leafStyle(.author)
                            Text(pick.reason.text)
                                .leafStyle(.caption)
                                .italic()
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.xxs)
                            Text("\(LeafFormat.number(pick.book.pages)) pages · about \(LeafFormat.duration(minutes: pick.book.minutes(atWPM: wpm))) at your pace")
                                .leafStyle(.caption)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens book details")
                HStack(spacing: Space.l) {
                    TextButton("Keep for later", color: .accent) {
                        onKeep()
                    }
                    TextButton("Not for me", color: .inkSecondary) {
                        onPass()
                    }
                }
            }
        }
    }
}

// MARK: - Week

struct WeekCard: View {
    let days: [DayStat]
    let goalMinutes: Int
    let streak: Int
    let cupMinutes: Int

    var body: some View {
        TodayCard("This week") {
            TeaRingWeek(days: days, goalMinutes: goalMinutes, streak: streak, cupMinutes: cupMinutes)
        }
    }
}

// MARK: - Year goal

/// Books finished against the year's goal, with the plain arithmetic and, once the forecast is in, its range.
struct YearGoalCard: View {
    let pacing: YearGoalPacing
    var forecastSentence: String?

    private var goal: Int { pacing.goal ?? 0 }

    var body: some View {
        TodayCard("\(String(pacing.year)) goal") {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(pacing.finished)")
                        .leafStyle(.statNumeral)
                    Text("of \(goal) books")
                        .leafStyle(.caption)
                }
                .accessibilityElement(children: .combine)
                ProgressBar(progress: goal > 0 ? min(1, Double(pacing.finished) / Double(goal)) : 0, tint: .accent, height: 3)
                Text(pacingSentence)
                    .leafStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let forecastSentence {
                    Text(forecastSentence)
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pacingSentence: String { pacing.sentence }
}

// MARK: - Challenge

struct ChallengeCard: View {
    let progress: ChallengeProgress

    private var challenge: Challenge? { ChallengeCatalog.all.first { $0.id == progress.challengeID } }

    var body: some View {
        TodayCard("Challenge") {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(challenge?.title ?? "Your challenge")
                    .leafStyle(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressBar(progress: progress.fraction, tint: CozyColor.color(for: challenge?.paletteToken ?? CozyPalette.chai), height: 3)
                Text(countLine)
                    .leafStyle(.caption)
                Text(progress.statusLine)
                    .leafStyle(.body, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var countLine: String {
        let unit = challenge?.unitName(for: progress.target) ?? "steps"
        return "\(progress.current) of \(progress.target) \(unit)"
    }
}

// MARK: - Quote

struct QuoteCard: View {
    let entry: JournalEntry
    var onCard: (() -> Void)?

    var body: some View {
        TodayCard(
            entry.kind == .quote ? "From your journal" : "A note you left",
            actionTitle: entry.kind == .quote && onCard != nil ? "Make a card" : nil,
            action: entry.kind == .quote ? onCard : nil
        ) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("“\(entry.text)”")
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
                Text(attribution)
                    .leafStyle(.caption)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var attribution: String {
        if let page = entry.page { return "\(entry.bookTitle), p. \(page)" }
        return entry.bookTitle
    }
}

// MARK: - Nudge

/// A gentle prompt from the engine, with the one or two things it suggests.
struct NudgeCard: View {
    struct Action: Identifiable {
        let title: String
        var isQuiet = false
        let perform: () -> Void
        var id: String { title }
    }

    let nudge: TodayNudge
    let actions: [Action]

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Text(nudge.text)
                    .leafStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !actions.isEmpty {
                HStack(spacing: Space.l) {
                    ForEach(actions) { action in
                        TextButton(action.title, color: action.isQuiet ? Color.inkSecondary : Color.accent) {
                            Haptics.shared.tap()
                            action.perform()
                        }
                    }
                }
                .padding(.leading, 20 + Space.m)
            }
        }
        .canopyCard(padding: Space.l, radius: Canopy.Radius.card, tint: .forest)
    }

    private var symbol: String {
        switch nudge.kind {
        case .confirmPosition: "bookmark"
        case .stalledBook: "hourglass"
        case .pausedBookWaiting: "book.closed"
        case .challengeEnding: "seal"
        case .yearGoalBehind: "leaf"
        }
    }
}

// MARK: - Reading-slot words

/// Shared words for reading times, on Today and in the editor.
enum ReadingSlotText {
    /// A name for a time that hasn't been given one: "Morning", "Lunch", "Evening", "Before bed".
    static func defaultLabel(hour: Int) -> String {
        switch hour {
        case 4..<11: "Morning"
        case 11..<14: "Lunch"
        case 14..<17: "Afternoon"
        case 17..<21: "Evening"
        default: "Before bed"
        }
    }

    /// "Every reading day", "Weekdays", "Weekends", or "Mon, Wed, Fri".
    static func days(_ weekdays: Set<Int>?, calendar: Calendar = .current) -> String {
        guard let weekdays, !weekdays.isEmpty, weekdays.count < 7 else { return "Every reading day" }
        if weekdays == [2, 3, 4, 5, 6] { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday
        let ordered = (0..<7).map { ((first - 1 + $0) % 7) + 1 }.filter { weekdays.contains($0) }
        return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
