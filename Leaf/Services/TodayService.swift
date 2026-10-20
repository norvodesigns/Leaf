import Foundation
import Observation

/// The forecast, computed off the main thread and kept until something changes.
///
/// A forecast runs a couple of thousand simulated futures, which is quick but not free, so screens ask this service
/// rather than building a `ForecastEngine` in a view. Pass the same seed to the baseline and to any what-if so the
/// difference between them is the change itself.
@MainActor
@Observable
final class ForecastService {
    private(set) var result: ForecastResult?
    private(set) var isWorking = false
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Recomputes from the store's current data. Cancels a run that is still going.
    func refresh(from store: LibraryStore) {
        let data = store.data
        let now = store.now
        let calendar = store.calendar
        let seed = SeededGenerator.daySeed(now, calendar: calendar)
        task?.cancel()
        isWorking = true
        task = Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) {
                ForecastEngine(data: data, now: now, calendar: calendar).forecast(seed: seed)
            }.value
            guard !Task.isCancelled else { return }
            self?.result = computed
            self?.isWorking = false
            WatchBridge.shared.forecast = computed
        }
    }

    /// The forecast with a different daily time or set of reading days (the what-if sliders).
    func whatIf(dailyMinutes: Int?, readingDays: Set<Int>?, store: LibraryStore) async -> ForecastResult {
        let data = store.data
        let now = store.now
        let calendar = store.calendar
        let seed = SeededGenerator.daySeed(now, calendar: calendar)
        return await Task.detached(priority: .userInitiated) {
            ForecastEngine(data: data, now: now, calendar: calendar).whatIf(dailyMinutes: dailyMinutes, readingDays: readingDays, seed: seed)
        }.value
    }

    /// "Probably done Sunday, between Saturday and Tuesday." for a book, once a forecast exists.
    func sentence(for bookID: String, store: LibraryStore) -> String? {
        guard let forecast = result?.book(bookID) else { return nil }
        return ForecastNarrator(now: store.now, calendar: store.calendar).bookSentence(forecast)
    }
}

/// Remembers the last greetings so the line doesn't flicker on re-render and never repeats yesterday's.
enum GreetingMemoryStore {
    private static let memoryKey = "leaf.greeting.memory"
    private static let lastShownKey = "leaf.greeting.lastShownDay"

    static func load() -> GreetingMemory {
        guard let data = UserDefaults.standard.data(forKey: memoryKey), let memory = try? JSONDecoder().decode(GreetingMemory.self, from: data) else { return GreetingMemory() }
        return memory
    }

    static func save(_ memory: GreetingMemory) {
        if let data = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(data, forKey: memoryKey) }
    }

    static func lastShownDay() -> String? { UserDefaults.standard.string(forKey: lastShownKey) }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

extension LibraryStore {
    /// Everything the Today screen draws, worked out in one place.
    ///
    /// Call it from the screen's body or a `.task`, and call `markGreetingShown(_:)` once when the greeting appears so
    /// tomorrow's line differs and "first time today" lines don't repeat on every visit.
    func todayBrief(catalog: BookCatalog, forecast: ForecastResult? = nil, weather: CozyWeather? = nil) -> TodayBrief {
        var memory = GreetingMemoryStore.load()
        let previous = memory.previousLineID(on: now, calendar: calendar)
        let isFirstToday = GreetingMemoryStore.lastShownDay() != GreetingMemoryStore.dayKey(now, calendar: calendar)
        let input = TodayBriefInput(
            data: data, plan: plan, now: now, calendar: calendar, weather: weather,
            isFirstLaunchOfDay: isFirstToday, previousGreetingID: previous,
            candidates: catalog.books, stats: catalog.stats
        )
        var brief = TodayBriefBuilder.build(input)
        if let forecast, let bookID = brief.current?.item.id, let bookForecast = forecast.book(bookID) {
            brief.forecastSentence = ForecastNarrator(now: now, calendar: calendar).bookSentence(bookForecast)
        }
        return brief
    }

    func markGreetingShown(_ brief: TodayBrief) {
        var memory = GreetingMemoryStore.load()
        memory.record(brief.greeting, on: now, calendar: calendar)
        GreetingMemoryStore.save(memory)
        UserDefaults.standard.set(GreetingMemoryStore.dayKey(now, calendar: calendar), forKey: "leaf.greeting.lastShownDay")
        WatchBridge.shared.noteGreeting(brief.greeting, now: now, calendar: calendar)
    }
}
