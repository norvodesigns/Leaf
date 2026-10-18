import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The optional on-device librarian (NEXT.md sections 5 and 16): Apple Intelligence writes a fresh greeting line, privately,
/// on the device. It is sugar over the template engine and nothing depends on it.
///
/// - It only runs when the reader turned on `preferences.aiGreetings` and `SystemLanguageModel.default.availability` says
///   the model is ready right now.
/// - It only rewrites the ambient greetings (time of day, weather, season, weekday, moon, book flavour). Anything with a
///   real fact in it (pages left, a finished book, a streak, a holiday) stays with the templates.
/// - The prompt is tightly constrained, the answer is checked by the same tone rules the tests apply to the whole pool
///   (`AIGreetingPrompt.clean`), and any violation, error, timeout or unavailability falls back to the template line.
/// - One generated line is kept per daypart per day, so the greeting never changes under the reader and the model is not
///   asked again every time the screen appears.
enum AILibrarian {
    /// Whether the on-device model can write right now. Always false where `FoundationModels` does not exist.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// The writer to use. Templates unless the reader opted in and the model is ready.
    static func greetingWriter(for preferences: ReadingPreferences) -> any GreetingWriter {
        #if canImport(FoundationModels)
        if preferences.aiGreetings, isAvailable { return AIGreetingWriter() }
        #endif
        return TemplateGreetingWriter()
    }
}

#if canImport(FoundationModels)

/// Writes the greeting with the on-device model, and falls back to the template engine on any problem.
actor AIGreetingWriter: GreetingWriter {
    private let defaults: UserDefaults
    private let timeoutSeconds: Double
    private var inFlight: [String: Task<String?, Never>] = [:]

    private static let cacheKey = "leaf.aiGreetings.cache.v1"

    init(defaults: UserDefaults = .standard, timeoutSeconds: Double = 4) {
        self.defaults = defaults
        self.timeoutSeconds = timeoutSeconds
    }

    func greeting(for context: GreetingContext, seed: UInt64, previousLineID: String?) async -> Greeting {
        let template = GreetingEngine.line(for: context, seed: seed, previousLineID: previousLineID)
        guard AIGreetingPrompt.isEligible(template), AILibrarian.isAvailable else { return template }

        let day = Self.dayKey(for: context)
        let key = day + "." + context.daypart.rawValue
        var cache = loadCache()

        // Already asked for this part of today: reuse the answer, or the template if the answer was no good.
        if let stored = cache[key] {
            return Self.usable(stored, context: context, previousLineID: previousLineID) ?? template
        }

        let raw = await generate(key: key, prompt: AIGreetingPrompt.prompt(for: context))
        let text = raw.flatMap { AIGreetingPrompt.clean($0, context: context) }

        // Keep today's answers only, and remember a failure too (as an empty string) so we do not ask again all evening.
        cache = cache.filter { $0.key.hasPrefix(day + ".") }
        cache[key] = text ?? ""
        saveCache(cache)

        guard let text else { return template }
        return Self.usable(text, context: context, previousLineID: previousLineID) ?? template
    }

    /// Forgets every saved line (for example when the reader turns the option off).
    func clearCache() {
        defaults.removeObject(forKey: Self.cacheKey)
    }

    // MARK: Model

    /// One request per key at a time, so two quick redraws share one answer.
    private func generate(key: String, prompt: String) async -> String? {
        let task: Task<String?, Never>
        if let running = inFlight[key] {
            task = running
        } else {
            let timeout = timeoutSeconds
            task = Task { await Self.ask(prompt: prompt, timeout: timeout) }
            inFlight[key] = task
        }
        let answer = await task.value
        inFlight[key] = nil
        return answer
    }

    /// Asks the model for one line, giving up after `timeout` seconds. Returns nil on any error.
    private static func ask(prompt: String, timeout: Double) async -> String? {
        await withTaskGroup(of: String?.self, returning: String?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession(instructions: AIGreetingPrompt.instructions)
                    let response = try await session.respond(to: prompt)
                    return response.content
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0.5, timeout) * 1_000_000_000))
                return nil
            }
            guard let first = await group.next() else { return nil }
            group.cancelAll()
            return first
        }
    }

    // MARK: Cache

    private static func usable(_ stored: String, context: GreetingContext, previousLineID: String?) -> Greeting? {
        guard !stored.isEmpty, let text = AIGreetingPrompt.clean(stored, context: context) else { return nil }
        let greeting = AIGreetingPrompt.greeting(from: text, context: context)
        return greeting.lineID == previousLineID ? nil : greeting
    }

    private static func dayKey(for context: GreetingContext) -> String {
        let parts = context.calendar.dateComponents([.year, .month, .day], from: context.date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private func loadCache() -> [String: String] {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return decoded
    }

    private func saveCache(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }
}

#endif
