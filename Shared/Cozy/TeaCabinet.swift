import Foundation

// MARK: - The cabinet

/// A tea the reader owns: a tin of a catalog tea (with their own brand, notes and steep time) or a tea of their own.
/// Synced like a journal entry: the newest `updatedAt` wins, and a deletion leaves a tombstone.
struct CabinetTea: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// The catalog tea this is a tin of. Nil for a tea of the reader's own.
    var catalogID: String?
    var name: String
    var brand: String
    var family: TeaFamily
    /// The reader's own words about it ("from the market in Kyoto, smoky").
    var notes: String
    /// How long they steep it, for a regular cup.
    var steepSeconds: Int
    /// 1 to 5, or nil when not rated.
    var rating: Int?
    /// "Out of" it for now: it stays in the cabinet but the ritual doesn't offer it.
    var isOutOf: Bool
    var addedAt: Date
    var updatedAt: Date

    /// Prefix of the id a session saves for a tea of the reader's own.
    static let customPrefix = "custom."

    init(
        id: UUID = UUID(),
        catalogID: String? = nil,
        name: String,
        brand: String = "",
        family: TeaFamily,
        notes: String = "",
        steepSeconds: Int,
        rating: Int? = nil,
        isOutOf: Bool = false,
        addedAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.catalogID = catalogID
        self.name = name
        self.brand = brand
        self.family = family
        self.notes = notes
        self.steepSeconds = steepSeconds
        self.rating = rating.map { min(5, max(1, $0)) }
        self.isOutOf = isOutOf
        self.addedAt = addedAt
        self.updatedAt = updatedAt ?? addedAt
    }

    /// A tin of a catalog tea, as it comes.
    init(tin tea: Tea, now: Date) {
        self.init(catalogID: tea.id, name: tea.name, family: tea.family, steepSeconds: tea.steepSeconds, addedAt: now)
    }

    enum CodingKeys: String, CodingKey {
        case id, catalogID, name, brand, family, notes, steepSeconds, rating, isOutOf, addedAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let family = try c.decodeIfPresent(TeaFamily.self, forKey: .family) ?? .black
        let addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date(timeIntervalSince1970: 0)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            catalogID: try c.decodeIfPresent(String.self, forKey: .catalogID),
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            brand: try c.decodeIfPresent(String.self, forKey: .brand) ?? "",
            family: family,
            notes: try c.decodeIfPresent(String.self, forKey: .notes) ?? "",
            steepSeconds: try c.decodeIfPresent(Int.self, forKey: .steepSeconds) ?? family.defaultSteepSeconds,
            rating: try c.decodeIfPresent(Int.self, forKey: .rating),
            isOutOf: try c.decodeIfPresent(Bool.self, forKey: .isOutOf) ?? false,
            addedAt: addedAt,
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }

    /// What a session saves as `teaID`: the catalog id for a catalog tea, so stats and challenges keep counting it,
    /// else "custom." and this tea's id.
    var teaID: String { catalogID ?? CabinetTea.customPrefix + id.uuidString }

    /// "Earl Grey · Twinings", or just the name.
    var displayName: String {
        let trimmed = brand.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : "\(name) · \(trimmed)"
    }

    /// As a `Tea` the ritual and the cup can use: the catalog's own tea with this tin's name and steep time, or one
    /// built from the reader's details with the family's water temperature and caffeine.
    var tea: Tea {
        if let catalogID, var base = TeaCatalog.tea(id: catalogID) {
            base.name = name.isEmpty ? base.name : name
            base.steepSeconds = steepSeconds
            return base
        }
        let caffeine = family.defaultCaffeine
        let cap = { (part: Daypart) in TeaSuggester.caffeineCap(for: part) >= caffeine }
        return Tea(
            id: teaID, name: name.isEmpty ? family.title : name, family: family, steepSeconds: steepSeconds,
            celsius: family.defaultCelsius, fahrenheit: Int((Double(family.defaultCelsius) * 9 / 5 + 32).rounded()),
            caffeine: caffeine, notes: [], blurb: notes, seasons: Season.allCases,
            dayparts: Daypart.allCases.filter(cap), moods: [], paletteToken: family.defaultPaletteToken
        )
    }
}

extension TeaFamily {
    /// A starting steep time for a tea of the reader's own, before they set theirs.
    var defaultSteepSeconds: Int {
        switch self {
        case .green, .white: return 120
        case .matcha: return 60
        case .black, .oolong: return 240
        case .chai: return 300
        case .herbal, .rooibos: return 360
        }
    }

    var defaultCelsius: Int {
        switch self {
        case .green, .matcha: return 80
        case .white: return 85
        case .oolong: return 90
        case .black, .chai, .herbal, .rooibos: return 98
        }
    }

    /// The lowest caffeine among the catalog's own teas of the family, so a tea of the reader's own is never ruled out
    /// at an hour when Leaf would still offer one of its teas of that family.
    var defaultCaffeine: TeaCaffeine {
        TeaCatalog.all.filter { $0.family == self }.map(\.caffeine).min() ?? typicalCaffeine
    }

    /// For a family the catalog has no tea of.
    private var typicalCaffeine: TeaCaffeine {
        switch self {
        case .black, .matcha, .chai: return .high
        case .green, .oolong: return .medium
        case .white: return .low
        case .herbal, .rooibos: return .none
        }
    }

    var defaultPaletteToken: String {
        switch self {
        case .black: return CozyPalette.amber
        case .green, .matcha: return CozyPalette.matcha
        case .white: return CozyPalette.steam
        case .oolong, .chai: return CozyPalette.chai
        case .herbal: return CozyPalette.rose
        case .rooibos: return CozyPalette.rooibos
        }
    }
}

// MARK: - Tasting notes

/// How a cup came out.
enum TastingStrength: String, Codable, CaseIterable, Sendable {
    case light, justRight, strong

    var title: String {
        switch self {
        case .light: return "Light"
        case .justRight: return "Just right"
        case .strong: return "Strong"
        }
    }
}

/// The aroma words a tasting card offers. Saved as plain strings, so a word added later never breaks old notes.
enum TastingAroma {
    static let all = ["malty", "floral", "smoky", "fruity", "citrus", "grassy", "nutty", "spicy", "honeyed", "earthy", "creamy", "minty"]
}

/// A few words about a cup, written after a session with tea. Kept like a journal entry and synced the same way.
struct TastingNote: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// The tea's id as sessions save it (a catalog id, or "custom.<uuid>").
    var teaID: String
    /// Kept with the note so it still reads properly after the tea leaves the cabinet.
    var teaName: String
    var family: TeaFamily?
    var bookID: String?
    var sessionID: UUID?
    var strength: TastingStrength?
    var aromas: [String]
    /// 1 to 5, or nil when not rated yet.
    var rating: Int?
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        teaID: String,
        teaName: String,
        family: TeaFamily? = nil,
        bookID: String? = nil,
        sessionID: UUID? = nil,
        strength: TastingStrength? = nil,
        aromas: [String] = [],
        rating: Int? = nil,
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.teaID = teaID
        self.teaName = teaName
        self.family = family
        self.bookID = bookID
        self.sessionID = sessionID
        self.strength = strength
        self.aromas = aromas
        self.rating = rating.map { min(5, max(1, $0)) }
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, teaID, teaName, family, bookID, sessionID, strength, aromas, rating, text, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            teaID: try c.decodeIfPresent(String.self, forKey: .teaID) ?? "",
            teaName: try c.decodeIfPresent(String.self, forKey: .teaName) ?? "",
            family: try? c.decodeIfPresent(TeaFamily.self, forKey: .family),
            bookID: try c.decodeIfPresent(String.self, forKey: .bookID),
            sessionID: try c.decodeIfPresent(UUID.self, forKey: .sessionID),
            strength: try? c.decodeIfPresent(TastingStrength.self, forKey: .strength),
            aromas: try c.decodeIfPresent([String].self, forKey: .aromas) ?? [],
            rating: try c.decodeIfPresent(Int.self, forKey: .rating),
            text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
            createdAt: createdAt,
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

// MARK: - Finding a tea

/// The reader's teas and the catalog, as one place to look. Pure.
enum TeaShelf {
    /// A tea by the id a session saved: the catalog's, or one of the reader's own (also when it is a tin of a
    /// catalog tea, so their name and steep time win).
    static func tea(id: String?, cabinet: [CabinetTea]) -> Tea? {
        guard let id, !id.isEmpty else { return nil }
        if let own = tin(id: id, cabinet: cabinet) { return own.tea }
        return TeaCatalog.tea(id: id)
    }

    /// The reader's tea with this id. Two devices can each add a tin of the same catalog tea before they sync, so
    /// there may be two: the one in stock wins, then the one changed last.
    static func tin(id: String, cabinet: [CabinetTea]) -> CabinetTea? {
        var best: CabinetTea?
        for candidate in cabinet where candidate.teaID == id {
            guard let current = best else {
                best = candidate
                continue
            }
            if prefers(candidate, over: current) { best = candidate }
        }
        return best
    }

    private static func prefers(_ a: CabinetTea, over b: CabinetTea) -> Bool {
        if a.isOutOf != b.isOutOf { return !a.isOutOf }
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// The teas in stock, as `Tea`s, in the order they were added, each tea once.
    static func inStock(_ cabinet: [CabinetTea]) -> [Tea] {
        let kept = cabinet.filter { !$0.isOutOf }.sorted { (a: CabinetTea, b: CabinetTea) -> Bool in
            if a.addedAt != b.addedAt { return a.addedAt < b.addedAt }
            return a.id.uuidString < b.id.uuidString
        }
        var seen = Set<String>()
        var teas: [Tea] = []
        for candidate in kept where seen.insert(candidate.teaID).inserted {
            teas.append((tin(id: candidate.teaID, cabinet: cabinet) ?? candidate).tea)
        }
        return teas
    }

    /// Whether the reader can make this tea at all: a tea of theirs that hasn't run out, or (while they keep no teas
    /// in stock) any of Leaf's.
    static func isAvailable(_ id: String, cabinet: [CabinetTea]) -> Bool {
        if let own = tin(id: id, cabinet: cabinet) { return !own.isOutOf }
        return inStock(cabinet).isEmpty && TeaCatalog.tea(id: id) != nil
    }

    /// The tea with this id if it can be offered now: available, and within the hour's caffeine rule. Used for the
    /// reader's own choices (a pinned pairing, a tea picked on Today), which are judged by the rule, not by rank.
    static func offerable(_ id: String?, cabinet: [CabinetTea], daypart: Daypart) -> Tea? {
        guard let id, isAvailable(id, cabinet: cabinet), let tea = tea(id: id, cabinet: cabinet) else { return nil }
        return tea.caffeine <= TeaSuggester.caffeineCap(for: daypart) ? tea : nil
    }

    /// What the ritual offers, best first, and whether it came from the reader's own cabinet.
    struct Choices: Hashable, Sendable {
        var teas: [Tea]
        /// False when the cabinet is empty, everything is out, or nothing in it suits the hour (the catalog fills in).
        var fromCabinet: Bool
        /// True when the cabinet has teas in stock but none is right for the hour (caffeine late at night).
        var cabinetUnsuitable: Bool
    }

    /// The ritual's teas: what the reader has, ranked for the hour (caffeine rules included); the catalog when the
    /// cabinet has nothing in stock or nothing that suits the hour. A book's pinned tea leads whenever it can be
    /// offered, however it ranks.
    static func ritualChoices(
        cabinet: [CabinetTea],
        daypart: Daypart,
        season: Season,
        favoriteTeaID: String? = nil,
        lastTeaID: String? = nil,
        seed: UInt64 = 0,
        limit: Int = 8,
        pinnedTeaID: String? = nil
    ) -> Choices {
        var choices = rankedChoices(
            cabinet: cabinet, daypart: daypart, season: season, favoriteTeaID: favoriteTeaID, lastTeaID: lastTeaID,
            seed: seed, limit: limit
        )
        if let pinned = offerable(pinnedTeaID, cabinet: cabinet, daypart: daypart) {
            choices.teas.removeAll { $0.id == pinned.id }
            choices.teas.insert(pinned, at: 0)
            if choices.teas.count > max(1, limit) { choices.teas.removeLast(choices.teas.count - max(1, limit)) }
        }
        return choices
    }

    private static func rankedChoices(
        cabinet: [CabinetTea],
        daypart: Daypart,
        season: Season,
        favoriteTeaID: String?,
        lastTeaID: String?,
        seed: UInt64,
        limit: Int
    ) -> Choices {
        let stock = inStock(cabinet)
        if !stock.isEmpty {
            let ranked = TeaSuggester.ranked(
                daypart: daypart, season: season, lastTeaID: lastTeaID, favoriteTeaID: favoriteTeaID,
                seed: seed, limit: limit, from: stock
            )
            if !ranked.isEmpty { return Choices(teas: ranked, fromCabinet: true, cabinetUnsuitable: false) }
        }
        let catalog = TeaSuggester.ranked(
            daypart: daypart, season: season, lastTeaID: lastTeaID, favoriteTeaID: favoriteTeaID, seed: seed, limit: limit
        )
        return Choices(teas: catalog, fromCabinet: false, cabinetUnsuitable: !stock.isEmpty)
    }

    /// The tea to start the ritual with for a book: the reader's pinned pairing when it is on offer, else the best
    /// pairing among the choices, else the first choice.
    static func preferred(for book: Book?, pinnedTeaID: String?, choices: [Tea]) -> Tea? {
        if let pinnedTeaID, let pinned = choices.first(where: { $0.id == pinnedTeaID }) { return pinned }
        if let book, let pick = TeaPairing.best(for: book, from: choices) { return pick.tea }
        return choices.first
    }
}
