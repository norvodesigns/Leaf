import Foundation

// The voice's shared plumbing: which facts a line may mention, how a template with {placeholders} is filled, and how
// every surface (greeting, notification, wrap-up, Live Activity, watch, weekly letter) picks a line from a seed.

/// The facts a line of copy is allowed to mention. Every field is optional. A template that names a fact we do not
/// have is simply never chosen, so a line can never print "{title}" or "0 pages".
struct VoiceValues: Equatable, Sendable {
    var title: String?
    /// Pages left in the book.
    var pagesLeft: Int?
    /// Days in a row. Only a run of two or more is ever mentioned.
    var streak: Int?
    /// Minutes, usually to today's goal.
    var minutes: Int?
    var tea: String?
    /// The weekday's English name.
    var day: String?
    /// Spell small numbers out ("eleven pages"), or keep digits ("11 pages") for tight places like a lock screen.
    var spellsNumbers = true
    /// The longest book title to print before it is shortened with an ellipsis.
    var maxTitleCharacters = 40

    init(
        title: String? = nil,
        pagesLeft: Int? = nil,
        streak: Int? = nil,
        minutes: Int? = nil,
        tea: String? = nil,
        day: String? = nil,
        spellsNumbers: Bool = true,
        maxTitleCharacters: Int = 40
    ) {
        self.title = title
        self.pagesLeft = pagesLeft
        self.streak = streak
        self.minutes = minutes
        self.tea = tea
        self.day = day
        self.spellsNumbers = spellsNumbers
        self.maxTitleCharacters = maxTitleCharacters
    }

    /// The placeholders this set of facts can fill.
    var available: Set<VoicePlaceholder> {
        var result: Set<VoicePlaceholder> = []
        if VoiceText.clean(title) != nil { result.insert(.title) }
        if let pagesLeft, pagesLeft >= 1 { result.insert(.pages) }
        if let streak, streak >= 2 { result.insert(.streak) }
        if let minutes, minutes >= 1 { result.insert(.minutes) }
        if VoiceText.clean(tea) != nil { result.insert(.tea) }
        if VoiceText.clean(day) != nil { result.insert(.day) }
        return result
    }
}

/// The words a template may put in braces.
enum VoicePlaceholder: String, CaseIterable, Sendable {
    /// The book's title, shortened if long.
    case title
    /// Pages left, as a phrase: "eleven pages", "one page", "34 pages".
    case pages
    /// A run of days, as a number: "seven", "21".
    case streak
    /// Minutes, as a phrase: "thirteen minutes", "one minute", "25 minutes".
    case minutes
    /// The tea's name.
    case tea
    /// The weekday: "Sunday".
    case day

    var token: String { "{" + rawValue + "}" }
}

enum VoiceText {
    // MARK: Words and numbers

    private static let numberWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
    ]

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "seven" for 7. Numbers above twenty stay as digits, which reads better than "thirty-seven".
    static func count(_ number: Int, spelled: Bool = true) -> String {
        if spelled, number >= 0, number < numberWords.count { return numberWords[number] }
        return String(number)
    }

    /// "one page", "eleven pages", "34 pages".
    static func pagesPhrase(_ pages: Int, spelled: Bool = true) -> String {
        "\(count(pages, spelled: spelled)) \(pages == 1 ? "page" : "pages")"
    }

    /// "one minute", "thirteen minutes", "25 minutes".
    static func minutesPhrase(_ minutes: Int, spelled: Bool = true) -> String {
        "\(count(minutes, spelled: spelled)) \(minutes == 1 ? "minute" : "minutes")"
    }

    /// The English name of a calendar weekday (1 = Sunday). Fixed English so it never depends on the device locale.
    static func weekdayName(_ weekday: Int) -> String {
        let index = ((weekday - 1) % 7 + 7) % 7
        return weekdayNames[index]
    }

    // MARK: Cleaning

    /// Trimmed text, or nil if there is nothing in it.
    static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// A book title short enough for a headline: no subtitle after a colon or bracket, at most six words, and at most
    /// `maxCharacters` characters, with an ellipsis when something was cut.
    static func shortTitle(_ title: String, maxWords: Int = 6, maxCharacters: Int = 40) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = trimmed
        for separator in [":", " (", " – ", " — ", " - "] {
            if let range = base.range(of: separator), range.lowerBound > base.startIndex {
                base = String(base[..<range.lowerBound])
            }
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = trimmed }

        var words = base.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var cut = false
        if words.count > max(1, maxWords) {
            words = Array(words.prefix(max(1, maxWords)))
            cut = true
        }
        var result = words.joined(separator: " ")
        let limit = max(4, maxCharacters)
        if result.count > limit {
            var clipped = String(result.prefix(limit - 1))
            if let space = clipped.lastIndex(of: " "), clipped.distance(from: clipped.startIndex, to: space) >= limit / 2 {
                clipped = String(clipped[..<space])
            }
            result = clipped.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.-–—"))
            cut = true
        }
        return cut ? result + "…" : result
    }

    static func capitalizingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Choosing

    /// Picks one item by weight, deterministically: the same seed and salt always pick the same item.
    /// `salt` keeps different decisions made from one daily seed independent of each other.
    static func choose<T>(_ items: [T], seed: UInt64, salt: String, weight: (T) -> Double = { _ in 1 }) -> T? {
        guard !items.isEmpty else { return nil }
        var rng = SeededGenerator(seed: seed ^ SeededGenerator.hash(salt))
        let weights = items.map { max(0, weight($0)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return items[Int(rng.next() % UInt64(items.count))] }
        var target = rng.unit() * total
        for (item, w) in zip(items, weights) {
            target -= w
            if target < 0 { return item }
        }
        return items.last
    }

    /// A deterministic yes or no with the given chance.
    static func chance(_ probability: Double, seed: UInt64, salt: String) -> Bool {
        var rng = SeededGenerator(seed: seed ^ SeededGenerator.hash(salt))
        return rng.unit() < probability
    }

    /// A stable short id for a piece of copy, from its text. Never `Hasher`, which is re-seeded every launch.
    static func stableID(_ prefix: String, _ text: String) -> String {
        let hash = SeededGenerator.hash(text) & 0xFFFF_FFFF
        let hex = String(hash, radix: 16)
        return prefix + "." + String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }
}

/// Filling and inspecting `{placeholder}` templates.
enum VoiceTemplate {
    /// The names between braces, in order, whether or not they are supported.
    static func tokens(in template: String) -> [String] {
        var result: [String] = []
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let close = template[index...].firstIndex(of: "}") {
                result.append(String(template[template.index(after: index)..<close]))
                index = template.index(after: close)
            } else {
                index = template.index(after: index)
            }
        }
        return result
    }

    /// The supported placeholders a template uses.
    static func placeholders(in template: String) -> Set<VoicePlaceholder> {
        Set(tokens(in: template).compactMap(VoicePlaceholder.init(rawValue:)))
    }

    /// Anything in braces that is not a supported placeholder, plus any stray brace. Empty means the template is sound.
    static func problems(in template: String) -> [String] {
        var result: [String] = []
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "{" {
                if let close = template[index...].firstIndex(of: "}") {
                    let name = String(template[template.index(after: index)..<close])
                    if VoicePlaceholder(rawValue: name) == nil { result.append(name) }
                    index = template.index(after: close)
                    continue
                }
                result.append("{")
            } else if char == "}" {
                result.append("}")
            }
            index = template.index(after: index)
        }
        return result
    }

    /// The template with every placeholder filled, or nil if any of them cannot be.
    static func fill(_ template: String, with values: VoiceValues) -> String? {
        fill(template, with: values, available: values.available)
    }

    /// Same, for callers that fill many templates from one set of facts and have worked out `available` once.
    static func fill(_ template: String, with values: VoiceValues, available: Set<VoicePlaceholder>) -> String? {
        guard template.contains("{") else { return template }
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let char = template[index]
            if char == "{", let close = template[index...].firstIndex(of: "}") {
                let name = String(template[template.index(after: index)..<close])
                guard let placeholder = VoicePlaceholder(rawValue: name), available.contains(placeholder),
                      let text = render(placeholder, values: values, startsSentence: startsSentence(output))
                else { return nil }
                output += text
                index = template.index(after: close)
            } else {
                output.append(char)
                index = template.index(after: index)
            }
        }
        return output
    }

    private static func startsSentence(_ output: String) -> Bool {
        guard let last = output.trimmingCharacters(in: .whitespaces).last else { return true }
        return ".?…".contains(last)
    }

    private static func render(_ placeholder: VoicePlaceholder, values: VoiceValues, startsSentence: Bool) -> String? {
        let spelled = values.spellsNumbers
        let text: String?
        switch placeholder {
        case .title:
            return VoiceText.clean(values.title).map { VoiceText.shortTitle($0, maxCharacters: values.maxTitleCharacters) }
        case .tea:
            return VoiceText.clean(values.tea)
        case .day:
            return VoiceText.clean(values.day)
        case .pages:
            text = values.pagesLeft.map { VoiceText.pagesPhrase($0, spelled: spelled) }
        case .streak:
            text = values.streak.map { VoiceText.count($0, spelled: spelled) }
        case .minutes:
            text = values.minutes.map { VoiceText.minutesPhrase($0, spelled: spelled) }
        }
        guard let text else { return nil }
        return startsSentence ? VoiceText.capitalizingFirst(text) : text
    }
}
