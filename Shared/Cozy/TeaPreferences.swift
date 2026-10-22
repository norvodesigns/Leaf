import Foundation

/// How much caffeine the reader wants, on top of the engine's own rule for the hour (which always applies).
enum TeaCaffeineChoice: String, Codable, CaseIterable, Sendable {
    /// Whatever suits the hour.
    case any
    /// Caffeine before lunch, none after.
    case morningsOnly
    /// A little at most.
    case low
    /// Caffeine free.
    case none

    var title: String {
        switch self {
        case .any: return "Any"
        case .morningsOnly: return "Mornings only"
        case .low: return "Low"
        case .none: return "None"
        }
    }

    /// The most caffeine this choice allows at this hour.
    func cap(at daypart: Daypart) -> TeaCaffeine {
        switch self {
        case .any: return .high
        case .morningsOnly:
            switch daypart {
            case .dawn, .morning, .lunch: return .high
            default: return .none
            }
        case .low: return .low
        case .none: return .none
        }
    }
}

/// The three broad times of day a reader can pick teas for.
enum TeaTimeOfDay: String, Codable, CaseIterable, Sendable {
    case morning, afternoon, evening

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    static func of(_ daypart: Daypart) -> TeaTimeOfDay {
        switch daypart {
        case .dawn, .morning, .lunch: return .morning
        case .afternoon, .teaTime: return .afternoon
        case .dusk, .evening, .late, .smallHours: return .evening
        }
    }
}

/// What the reader likes in a tea: kinds, caffeine, flavours, and (optionally) kinds for a time of day. Suggestions
/// lean toward these; the caffeine choice is a limit. An empty value changes nothing.
struct TeaPreferences: Codable, Hashable, Sendable {
    var likedFamilies: Set<TeaFamily> = []
    var caffeine: TeaCaffeineChoice = .any
    /// Flavour words from `TastingAroma.all` ("floral", "malty"…), matched against a tea's tasting notes.
    var likedFlavours: Set<String> = []
    /// Kinds for a time of day: "herbal in the evening".
    var familiesByTime: [TeaTimeOfDay: Set<TeaFamily>] = [:]

    init(
        likedFamilies: Set<TeaFamily> = [],
        caffeine: TeaCaffeineChoice = .any,
        likedFlavours: Set<String> = [],
        familiesByTime: [TeaTimeOfDay: Set<TeaFamily>] = [:]
    ) {
        self.likedFamilies = likedFamilies
        self.caffeine = caffeine
        self.likedFlavours = likedFlavours
        self.familiesByTime = familiesByTime
    }

    enum CodingKeys: String, CodingKey {
        case likedFamilies, caffeine, likedFlavours, familiesByTime
    }

    /// Tolerant: anything unreadable (a newer build's family, say) falls back to "no preference".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        likedFamilies = (try? c.decodeIfPresent(Set<TeaFamily>.self, forKey: .likedFamilies)) ?? []
        caffeine = (try? c.decodeIfPresent(TeaCaffeineChoice.self, forKey: .caffeine)) ?? .any
        likedFlavours = (try? c.decodeIfPresent(Set<String>.self, forKey: .likedFlavours)) ?? []
        familiesByTime = (try? c.decodeIfPresent([TeaTimeOfDay: Set<TeaFamily>].self, forKey: .familiesByTime)) ?? [:]
    }

    var isEmpty: Bool {
        likedFamilies.isEmpty && caffeine == .any && likedFlavours.isEmpty && familiesByTime.values.allSatisfy(\.isEmpty)
    }

    // MARK: Weights

    /// A liked kind: enough to beat a slightly better seasonal fit.
    static let likedFamilyWeight = 2.5
    /// A kind picked for this time of day: the strongest pull.
    static let timeOfDayWeight = 3.0
    /// A kind left out of this time of day's picks, when there are picks.
    static let offTimePenalty = 1.0
    /// Each liked flavour in the tea's notes, up to `flavourCap`.
    static let flavourWeight = 0.8
    static let flavourCap = 2.4

    /// Whether the caffeine choice lets this tea be offered at this hour.
    func allows(_ tea: Tea, at daypart: Daypart) -> Bool {
        tea.caffeine <= caffeine.cap(at: daypart)
    }

    /// How much these preferences lean toward a tea at this hour (added to the suggester's fit).
    func score(_ tea: Tea, at daypart: Daypart) -> Double {
        var score = 0.0
        if likedFamilies.contains(tea.family) { score += Self.likedFamilyWeight }
        if let picks = familiesByTime[TeaTimeOfDay.of(daypart)], !picks.isEmpty {
            score += picks.contains(tea.family) ? Self.timeOfDayWeight : -Self.offTimePenalty
        }
        if !likedFlavours.isEmpty {
            let notes = tea.notes.map { $0.lowercased() }
            let matches = likedFlavours.filter { flavour in notes.contains { $0.contains(flavour.lowercased()) } }.count
            score += min(Self.flavourCap, Double(matches) * Self.flavourWeight)
        }
        return score
    }
}
