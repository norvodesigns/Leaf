import Foundation

/// A time of day the reader sets aside for reading. A reader can have several: a few pages with morning tea, a
/// longer stretch in the evening, and with more than one book on the go, a book for each.
struct ReadingSlot: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int
    /// Calendar weekdays (1 = Sunday ... 7 = Saturday) the slot applies to, or nil for every reading day.
    var weekdays: Set<Int>?
    /// The book this time is for ("mornings are for Circe"), or nil to read whatever the plan says is next.
    var bookID: String?
    /// A name for the time, like "Morning tea" or "Before bed".
    var label: String?
    var isEnabled: Bool

    init(id: UUID = UUID(), hour: Int, minute: Int = 0, weekdays: Set<Int>? = nil, bookID: String? = nil, label: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.weekdays = weekdays
        self.bookID = bookID
        self.label = label
        self.isEnabled = isEnabled
    }

    var minuteOfDay: Int { hour * 60 + minute }

    func applies(onWeekday weekday: Int) -> Bool {
        weekdays?.contains(weekday) ?? true
    }

    /// The identity of the single reminder time every reader had before slots existed.
    static let legacyID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
}

extension ReadingPreferences {
    /// The reader's reading times. Before slots existed there was one reminder time; it still counts if reminders are on.
    var effectiveReadingSlots: [ReadingSlot] {
        if !readingSlots.isEmpty { return readingSlots }
        guard reminderEnabled else { return [] }
        return [ReadingSlot(id: ReadingSlot.legacyID, hour: reminderHour, minute: reminderMinute)]
    }
}

/// One stretch of one book inside a reading time.
struct SlotPart: Hashable, Identifiable, Sendable {
    var bookID: String
    var minutes: Double
    var fromPage: Int
    var toPage: Int
    var finishesBook: Bool

    var id: String { "\(bookID)-\(fromPage)" }
}

/// What a reading time is for today.
struct SlotPlan: Hashable, Identifiable, Sendable {
    var slot: ReadingSlot
    var parts: [SlotPart]

    var id: UUID { slot.id }
    var minutes: Double { parts.reduce(0) { $0 + $1.minutes } }
}

/// Spreads one day's reading across the reader's reading times.
///
/// The plan decides how much of each book to read today; the slots decide when. A slot tied to a book gets that
/// book's share; the rest are filled in plan order. One book can span several slots (its pages are split between them
/// in order), and several books can share one slot when there are more books than times. Whatever the arrangement,
/// every minute and page of the day's plan lands in exactly one slot.
enum SlotPlanner {
    static func plan(day: PlanDay, slots: [ReadingSlot], calendar: Calendar = .current) -> [SlotPlan] {
        let weekday = calendar.component(.weekday, from: day.date)
        let active = slots
            .filter { $0.isEnabled && $0.applies(onWeekday: weekday) }
            .sorted { ($0.minuteOfDay, $0.id.uuidString) < ($1.minuteOfDay, $1.id.uuidString) }
        guard !active.isEmpty, !day.assignments.isEmpty else { return [] }

        let plannedBooks = Set(day.assignments.map(\.bookID))
        var pinned: [String: [ReadingSlot]] = [:]
        var free: [ReadingSlot] = []
        for slot in active {
            if let book = slot.bookID, plannedBooks.contains(book) {
                pinned[book, default: []].append(slot)
            } else {
                free.append(slot)
            }
        }

        var parts: [UUID: [SlotPart]] = [:]

        // Books with their own times read at those times.
        for assignment in day.assignments {
            guard let own = pinned[assignment.bookID] else { continue }
            for (slot, part) in zip(own, split(assignment, among: own.count)) {
                parts[slot.id, default: []].append(part)
            }
        }

        // The rest go to the open times, in plan order.
        let loose = day.assignments.filter { pinned[$0.bookID] == nil }
        if !loose.isEmpty {
            if free.isEmpty, let last = active.last {
                // Every time belongs to some other book; the leftovers read after the last one.
                parts[last.id, default: []].append(contentsOf: loose.map { split($0, among: 1)[0] })
            } else if loose.count >= free.count {
                for (index, assignment) in loose.enumerated() {
                    parts[free[index % free.count].id, default: []].append(split(assignment, among: 1)[0])
                }
            } else {
                // More open times than books: the biggest books get the extra times.
                var counts = Array(repeating: 1, count: loose.count)
                let bySize = loose.indices.sorted { loose[$0].minutes > loose[$1].minutes || (loose[$0].minutes == loose[$1].minutes && $0 < $1) }
                var extra = free.count - loose.count
                var cursor = 0
                while extra > 0 {
                    counts[bySize[cursor % bySize.count]] += 1
                    cursor += 1
                    extra -= 1
                }
                var next = 0
                for (index, assignment) in loose.enumerated() {
                    let mine = Array(free[next..<(next + counts[index])])
                    next += counts[index]
                    for (slot, part) in zip(mine, split(assignment, among: mine.count)) {
                        parts[slot.id, default: []].append(part)
                    }
                }
            }
        }

        return active.compactMap { slot in
            guard let own = parts[slot.id], !own.isEmpty else { return nil }
            return SlotPlan(slot: slot, parts: own)
        }
    }

    /// The next reading time that hasn't started yet on `day`, given the current moment.
    static func next(in plans: [SlotPlan], day: Date, now: Date, calendar: Calendar = .current) -> SlotPlan? {
        let start = calendar.startOfDay(for: day)
        return plans.first { plan in
            // By the clock on the wall: minutes since midnight are an hour out on the days the clocks change.
            let when = calendar.date(bySettingHour: plan.slot.hour, minute: plan.slot.minute, second: 0, of: start) ?? start
            return when >= now
        }
    }

    /// Splits one book's reading for the day into up to `count` consecutive stretches, sharing the minutes by pages.
    static func split(_ assignment: Assignment, among count: Int) -> [SlotPart] {
        let pages = max(0, assignment.toPage - assignment.fromPage + 1)
        let pieces = max(1, min(count, pages == 0 ? 1 : pages))
        if pieces == 1 {
            return [SlotPart(bookID: assignment.bookID, minutes: assignment.minutes, fromPage: assignment.fromPage, toPage: assignment.toPage, finishesBook: assignment.finishesBook)]
        }
        var result: [SlotPart] = []
        var start = assignment.fromPage
        for index in 0..<pieces {
            let last = index == pieces - 1
            let proposed = assignment.fromPage + Int((Double(pages) * Double(index + 1) / Double(pieces)).rounded()) - 1
            let end = last ? assignment.toPage : max(start, min(proposed, assignment.toPage))
            let share = Double(end - start + 1) / Double(pages)
            result.append(SlotPart(
                bookID: assignment.bookID, minutes: assignment.minutes * share, fromPage: start, toPage: end,
                finishesBook: assignment.finishesBook && last
            ))
            start = end + 1
        }
        return result
    }
}
