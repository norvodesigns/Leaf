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

/// What the reader likes in a tea: kinds, caffeine, flavours, (optionally) kinds for a time of day, and the leaves
/// they gave particular teas. Suggestions lean toward these; the caffeine choice is a limit. An empty value changes
/// nothing.
struct TeaPreferences: Codable, Hashable, Sendable {
    var likedFamilies: Set<TeaFamily> = []
    var caffeine: TeaCaffeineChoice = .any
    /// Flavour words from `TastingAroma.all` ("floral", "malty"…), matched against a tea's tasting notes.
    var likedFlavours: Set<String> = []
    /// Kinds for a time of day: "herbal in the evening".
    var familiesByTime: [TeaTimeOfDay: Set<TeaFamily>] = [:]
    /// Leaves for a tea, 1 to 5, by the id a session saves ("earl-grey", "custom.<uuid>"). A tin in the cabinet keeps
    /// its own rating, which wins (`TeaShelf.rating`).
    private(set) var ratings: [String: Int] = [:]

    init(
        likedFamilies: Set<TeaFamily> = [],
        caffeine: TeaCaffeineChoice = .any,
        likedFlavours: Set<String> = [],
        familiesByTime: [TeaTimeOfDay: Set<TeaFamily>] = [:],
        ratings: [String: Int] = [:]
    ) {
        self.likedFamilies = likedFamilies
        self.caffeine = caffeine
        self.likedFlavours = likedFlavours
        self.familiesByTime = familiesByTime
        for (id, rating) in ratings { setRating(rating, for: id) }
    }

    enum CodingKeys: String, CodingKey {
        case likedFamilies, caffeine, likedFlavours, familiesByTime, ratings
    }

    /// Tolerant: anything unreadable (a newer build's family, say) falls back to "no preference".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        likedFamilies = (try? c.decodeIfPresent(Set<TeaFamily>.self, forKey: .likedFamilies)) ?? []
        caffeine = (try? c.decodeIfPresent(TeaCaffeineChoice.self, forKey: .caffeine)) ?? .any
        likedFlavours = (try? c.decodeIfPresent(Set<String>.self, forKey: .likedFlavours)) ?? []
        familiesByTime = (try? c.decodeIfPresent([TeaTimeOfDay: Set<TeaFamily>].self, forKey: .familiesByTime)) ?? [:]
        for (id, rating) in (try? c.decodeIfPresent([String: Int].self, forKey: .ratings)) ?? [:] { setRating(rating, for: id) }
    }

    var isEmpty: Bool { !hasLeanings && ratings.isEmpty }

    /// Kinds, caffeine, flavours or times picked: what "Teas you like" sets and clears. Ratings are kept apart.
    var hasLeanings: Bool {
        !(likedFamilies.isEmpty && caffeine == .any && likedFlavours.isEmpty && familiesByTime.values.allSatisfy(\.isEmpty))
    }

    /// These preferences without the kinds, caffeine, flavours and times, keeping the ratings.
    var leaningsCleared: TeaPreferences { TeaPreferences(ratings: ratings) }

    // MARK: Ratings

    func rating(for teaID: String) -> Int? { ratings[teaID] }

    /// Gives a tea 1 to 5 leaves (clamped), or takes its rating away with nil.
    mutating func setRating(_ rating: Int?, for teaID: String) {
        guard !teaID.isEmpty else { return }
        ratings[teaID] = rating.map { min(5, max(1, $0)) }
    }

    /// With the ratings on the reader's tins laid over these, so the suggester weighs a cabinet tea by its tin.
    func withRatings(from cabinet: [CabinetTea]) -> TeaPreferences {
        var merged = self
        for tea in cabinet {
            if let rating = TeaShelf.tin(id: tea.teaID, cabinet: cabinet)?.rating { merged.setRating(rating, for: tea.teaID) }
        }
        return merged
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

    /// Five leaves pull a tea forward almost as far as a liked kind; one leaf all but retires it. Three is neutral.
    static func ratingWeight(_ rating: Int) -> Double {
        switch rating {
        case 5: return 2.0
        case 4: return 1.0
        case 2: return -1.0
        case 1: return -2.5
        default: return 0
        }
    }

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
            let matches = likedFlavours.filter { TastingAroma.tea(tea, tastesOf: $0) }.count
            score += min(Self.flavourCap, Double(matches) * Self.flavourWeight)
        }
        if let rating = ratings[tea.id] { score += Self.ratingWeight(rating) }
        return score
    }
}
