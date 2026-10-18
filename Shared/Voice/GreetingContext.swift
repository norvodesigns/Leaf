import Foundation

// Everything the greeting engine may know about the moment, as plain values. No store types: the app fills this in
// from whatever it has, and every field except the date and calendar has a sensible "I don't know" default, so the
// engine is good with no permissions at all (NEXT.md section 14).

/// Weather, only when the app happens to know it. Never required.
enum GreetingWeather: String, Codable, CaseIterable, Sendable {
    case clear, rain, snow, cold, hot, wind, fog, unknown
}

/// Days with a line of their own. The two "season" cases are windows (all of October, the first three weeks of
/// December); the rest are single days.
enum GreetingHoliday: String, CaseIterable, Sendable {
    case newYearsEve, newYear, valentines, easter, halloween, spookySeason, thanksgiving
    case christmasSeason, christmasEve, christmas

    /// Whether this is a stretch of weeks rather than one day.
    var isWindow: Bool { self == .spookySeason || self == .christmasSeason }

    /// The holiday on `date`, if any. Computed on the Gregorian calendar in the caller's time zone, so a reader whose
    /// device uses another calendar system still gets Halloween on October 31. Thanksgiving is the American one
    /// (fourth Thursday of November).
    static func of(_ date: Date, calendar: Calendar) -> GreetingHoliday? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day, let weekday = parts.weekday else { return nil }

        switch (month, day) {
        case (12, 31): return .newYearsEve
        case (1, 1): return .newYear
        case (2, 14): return .valentines
        case (10, 31): return .halloween
        case (12, 24): return .christmasEve
        case (12, 25): return .christmas
        default: break
        }
        // The fourth Thursday is always the 22nd to the 28th.
        if month == 11, weekday == 5, (22...28).contains(day) { return .thanksgiving }
        if let easter = easterSunday(year: year), easter.month == month, easter.day == day { return .easter }
        if month == 10 { return .spookySeason }
        if month == 12, day <= 23 { return .christmasSeason }
        return nil
    }

    /// Easter Sunday in the Gregorian calendar (the Meeus/Jones/Butcher algorithm).
    static func easterSunday(year: Int) -> (month: Int, day: Int)? {
        guard year > 1582, year < 9999 else { return nil }
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }
}

/// The moon, from a simple synodic-month formula. Good to about half a day, which is plenty for "full moon tonight".
enum GreetingMoonPhase: String, CaseIterable, Sendable {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent

    static let synodicMonth = 29.530_588_853
    /// A known new moon: 6 January 2000, 18:14 UTC, as seconds since 1970.
    private static let referenceNewMoon = 947_182_440.0

    /// Days since the last new moon, 0 to just under 29.53.
    static func age(of date: Date) -> Double {
        let days = (date.timeIntervalSince1970 - referenceNewMoon) / 86_400
        guard days.isFinite else { return 0 }
        var age = days.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }
        return age
    }

    static func of(_ date: Date) -> GreetingMoonPhase {
        let slot = Int((age(of: date) / synodicMonth * 8).rounded()) % 8
        return GreetingMoonPhase.allCases[slot]
    }
}

/// How the book the greeting is about is going.
enum GreetingBookState: Equatable, Sendable {
    /// No current book (or nothing worth saying about it).
    case none
    case justStarted
    case midway
    /// A few pages from the end.
    case nearFinish(pagesLeft: Int)
    case finishedToday
    /// Not read for a couple of weeks.
    case stalled

    /// A sensible state from plain numbers, so every caller draws the lines the same way.
    /// Near the end is the last twelfth of the book, but never fewer than 10 pages and never more than 30.
    static func classify(currentPage: Int, totalPages: Int, finishedToday: Bool = false, daysSinceLastRead: Int? = nil, stalledAfterDays: Int = 14) -> GreetingBookState {
        if finishedToday { return .finishedToday }
        guard totalPages > 0 else { return .none }
        let page = min(max(currentPage, 0), totalPages)
        let left = totalPages - page
        guard left > 0 else { return .none }
        let threshold = min(30, max(10, totalPages / 12))
        if page > 0, left <= threshold { return .nearFinish(pagesLeft: left) }
        if page > 0, let days = daysSinceLastRead, days >= stalledAfterDays { return .stalled }
        if Double(page) / Double(totalPages) < 0.12 { return .justStarted }
        return .midway
    }
}

/// Where the reader is against today's goal.
enum GreetingGoalState: String, Codable, CaseIterable, Sendable {
    case notStarted, partial, met
}

struct GreetingContext: Equatable, Sendable {
    var date: Date
    var calendar: Calendar
    /// Swaps the seasons for the southern hemisphere.
    var southernHemisphere: Bool
    var weather: GreetingWeather
    /// Days in a row, counting through today or yesterday (whatever the app calls the current streak).
    var streak: Int
    /// Whole days since the last session, or nil if they have never read.
    var daysSinceLastSession: Int?
    var bookState: GreetingBookState
    var bookTitle: String?
    var goalState: GreetingGoalState
    var isRestDay: Bool
    /// True for the first greeting of the calendar day. Work it out once per launch and keep it for the screen's life.
    var isFirstLaunchOfDay: Bool
    var isFirstEverLaunch: Bool
    var teaName: String?
    /// Minutes left to today's goal, when it is partly done.
    var minutesToGoal: Int?

    // Derived from the date. They are plain stored values so a test (or a preview) can set them directly.
    var daypart: Daypart
    var season: Season
    /// Calendar weekday, 1 = Sunday.
    var weekday: Int
    var holiday: GreetingHoliday?
    var moon: GreetingMoonPhase

    init(
        date: Date,
        calendar: Calendar,
        southernHemisphere: Bool = false,
        weather: GreetingWeather = .unknown,
        streak: Int = 0,
        daysSinceLastSession: Int? = nil,
        bookState: GreetingBookState = .none,
        bookTitle: String? = nil,
        goalState: GreetingGoalState = .notStarted,
        isRestDay: Bool = false,
        isFirstLaunchOfDay: Bool = true,
        isFirstEverLaunch: Bool = false,
        teaName: String? = nil,
        minutesToGoal: Int? = nil
    ) {
        self.date = date
        self.calendar = calendar
        self.southernHemisphere = southernHemisphere
        self.weather = weather
        self.streak = streak
        self.daysSinceLastSession = daysSinceLastSession
        self.bookState = bookState
        self.bookTitle = bookTitle
        self.goalState = goalState
        self.isRestDay = isRestDay
        self.isFirstLaunchOfDay = isFirstLaunchOfDay
        self.isFirstEverLaunch = isFirstEverLaunch
        self.teaName = teaName
        self.minutesToGoal = minutesToGoal
        self.daypart = Daypart.of(date, calendar: calendar)
        self.season = Season.of(date, calendar: calendar, southern: southernHemisphere)
        self.weekday = calendar.component(.weekday, from: date)
        self.holiday = GreetingHoliday.of(date, calendar: calendar)
        self.moon = GreetingMoonPhase.of(date)
    }

    var weekdayName: String { VoiceText.weekdayName(weekday) }
}
