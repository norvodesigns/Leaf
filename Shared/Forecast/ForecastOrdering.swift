import Foundation

/// What the reader wants from the order of their To read queue.
enum ForecastOrderGoal: Hashable, Sendable {
    /// Finish as many books as possible by this date (shortest first).
    case mostFinished(by: Date)
    /// Keep neighbouring books from sharing a genre.
    case alternateGenres
    /// Follow each heavy read with a short, light one.
    case palateCleanser
}

enum ForecastOrderReason: String, Hashable, Sendable {
    case shorterFirst
    case differentGenre
    case palateCleanser
}

/// One book that moved in the suggested order.
struct OrderChange: Hashable, Sendable {
    var bookID: String
    var fromIndex: Int
    var toIndex: Int
    var reason: ForecastOrderReason
}

/// How one queued book's finish changes if the suggestion is taken (median of the same simulated futures).
struct OrderDelta: Hashable, Sendable {
    var bookID: String
    var currentFinish: Date?
    var suggestedFinish: Date?
    /// Positive when the suggestion finishes it sooner.
    var daysEarlier: Int?
}

struct OrderSuggestion: Sendable {
    var goal: ForecastOrderGoal
    /// Queue book ids as they are now, and as suggested. The Reading shelf is never reordered.
    var currentOrder: [String]
    var suggestedOrder: [String]
    var changes: [OrderChange]
    var deltas: [OrderDelta]
    /// For `mostFinished`: books done by the target under `Planner` for each order (the suggestion is never lower).
    var finishedByTargetCurrent: Int?
    var finishedByTargetSuggested: Int?

    var isChange: Bool { suggestedOrder != currentOrder }
}

extension ForecastEngine {
    /// Suggests a better order for the To read queue. If nothing beats the current order, the current order comes back.
    func smartOrder(goal: ForecastOrderGoal, seed: UInt64 = 1, runs: Int = 600) -> OrderSuggestion {
        let current = queue
        let minutes: [String: Double] = Dictionary(uniqueKeysWithValues: current.map { ($0.id, expectedMinutesLeft($0)) })
        var counts: (current: Int, suggested: Int)?
        var suggested = current
        var reason = ForecastOrderReason.shorterFirst

        switch goal {
        case .mostFinished(let date):
            reason = .shorterFirst
            let day = calendar.startOfDay(for: date)
            let shortestFirst = current.enumerated().sorted {
                let a = minutes[$0.element.id] ?? 0, b = minutes[$1.element.id] ?? 0
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            func finishedCount(_ order: [LibraryItem]) -> Int {
                plan(queue: order).finishedCount(onOrBefore: day)
            }
            // Books that make the date go first, shortest first; the rest keep the order the reader chose.
            let shortPlan = plan(queue: shortestFirst)
            let makeIt = shortestFirst.filter { (shortPlan.book($0.id)?.finish ?? .distantFuture) <= day }
            let makeItIDs = Set(makeIt.map(\.id))
            let refined = makeIt + current.filter { !makeItIDs.contains($0.id) }
            let currentCount = finishedCount(current)
            var best = (order: current, count: currentCount)
            for candidate in [refined, shortestFirst] {
                let count = finishedCount(candidate)
                if count > best.count { best = (candidate, count) }
            }
            suggested = best.order
            counts = (currentCount, best.count)
        case .alternateGenres:
            reason = .differentGenre
            suggested = alternating(current, after: reading.last)
        case .palateCleanser:
            reason = .palateCleanser
            suggested = cleansing(current, minutes: minutes)
        }

        // Only ever offer a change that also holds up across the simulated futures.
        var deltas: [OrderDelta] = []
        let currentIDs = current.map(\.id)
        var suggestedIDs = suggested.map(\.id)
        if suggestedIDs != currentIDs {
            let before = ForecastSimulator.run(scenario(includeFuturePicks: false), seed: seed, runs: runs)
            let after = ForecastSimulator.run(scenario(queue: suggested, includeFuturePicks: false), seed: seed, runs: runs)
            if case .mostFinished(let date) = goal {
                let offset = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0)
                func expected(_ output: ForecastSimOutput) -> Double {
                    output.finishDays.reduce(0.0) { sum, sorted in
                        let done = sorted.filter { Int($0) <= offset }.count
                        return sum + Double(done) / Double(max(1, sorted.count))
                    }
                }
                if expected(after) + 1e-9 < expected(before) {
                    suggested = current
                    suggestedIDs = currentIDs
                    counts = counts.map { ($0.current, $0.current) }
                }
            }
            if suggestedIDs != currentIDs {
                let items = reading + queue
                let afterItems = reading + suggested
                for item in current {
                    let beforeIndex = items.firstIndex { $0.id == item.id }
                    let afterIndex = afterItems.firstIndex { $0.id == item.id }
                    let was = beforeIndex.flatMap { ForecastQuantile.offset(sorted: before.finishDays[$0], 0.5) }
                    let will = afterIndex.flatMap { ForecastQuantile.offset(sorted: after.finishDays[$0], 0.5) }
                    let origin = calendar.startOfDay(for: now)
                    deltas.append(OrderDelta(
                        bookID: item.id,
                        currentFinish: was.flatMap { calendar.date(byAdding: .day, value: $0, to: origin) },
                        suggestedFinish: will.flatMap { calendar.date(byAdding: .day, value: $0, to: origin) },
                        daysEarlier: was.flatMap { old in will.map { old - $0 } }
                    ))
                }
            }
        }

        var changes: [OrderChange] = []
        for (to, id) in suggestedIDs.enumerated() {
            guard let from = currentIDs.firstIndex(of: id), from != to else { continue }
            changes.append(OrderChange(bookID: id, fromIndex: from, toIndex: to, reason: reason))
        }
        return OrderSuggestion(
            goal: goal, currentOrder: currentIDs, suggestedOrder: suggestedIDs, changes: changes, deltas: deltas,
            finishedByTargetCurrent: counts?.current, finishedByTargetSuggested: counts?.suggested
        )
    }

    private func genre(_ item: LibraryItem) -> String { ForecastRecords.primaryGenre(of: item.book) }

    /// Keeps the order as it is except where two neighbours share a genre: the earliest book of a different genre
    /// steps forward instead, provided the books left can still be arranged without neighbours of one genre.
    private func alternating(_ items: [LibraryItem], after last: LibraryItem?) -> [LibraryItem] {
        var remaining = items
        var result: [LibraryItem] = []
        var previous = last.map(genre)

        /// Whether `books` can be laid out with no two neighbours alike, the first not matching `previous`.
        func arrangeable(_ books: [LibraryItem], previous: String?) -> Bool {
            var counts: [String: Int] = [:]
            for book in books { counts[genre(book), default: 0] += 1 }
            let n = books.count
            return counts.allSatisfy { name, count in count <= (name == previous ? n / 2 : (n + 1) / 2) }
        }

        while !remaining.isEmpty {
            let different = remaining.indices.filter { genre(remaining[$0]) != previous }
            let index = different.first { candidate in
                var rest = remaining
                let picked = rest.remove(at: candidate)
                return arrangeable(rest, previous: genre(picked))
            } ?? different.first ?? 0
            let next = remaining.remove(at: index)
            result.append(next)
            previous = genre(next)
        }
        return result
    }

    /// After a heavy read (clearly longer than the rest of the queue), the shortest light book steps up next, preferring a
    /// different genre.
    private func cleansing(_ items: [LibraryItem], minutes: [String: Double]) -> [LibraryItem] {
        guard items.count >= 3 else { return items }
        let sorted = items.compactMap { minutes[$0.id] }.sorted()
        let median = sorted[sorted.count / 2]
        let heavy = median * 1.5
        let light = median * 0.6
        var remaining = items
        var result: [LibraryItem] = []
        while !remaining.isEmpty {
            let next = remaining.removeFirst()
            result.append(next)
            guard (minutes[next.id] ?? 0) >= heavy else { continue }
            let candidates = remaining.enumerated().filter { (minutes[$0.element.id] ?? .infinity) <= light }
            let pick = candidates.min {
                let aSame = genre($0.element) == genre(next), bSame = genre($1.element) == genre(next)
                if aSame != bSame { return !aSame }
                let a = minutes[$0.element.id] ?? 0, b = minutes[$1.element.id] ?? 0
                return a == b ? $0.offset < $1.offset : a < b
            }
            if let pick, pick.offset != 0 {
                result.append(remaining.remove(at: pick.offset))
            }
        }
        return result
    }
}
