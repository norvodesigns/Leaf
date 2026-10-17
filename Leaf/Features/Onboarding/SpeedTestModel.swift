import Foundation

/// A stopwatch for the reading test. It pauses while the app is in the background, so a phone
/// call in the middle of the passage doesn't count as reading.
struct SpeedTestClock: Equatable {
    private(set) var accumulated: TimeInterval
    private(set) var runningSince: Date?

    init(accumulated: TimeInterval = 0, runningSince: Date? = nil) {
        self.accumulated = max(0, accumulated)
        self.runningSince = runningSince
    }

    var isRunning: Bool { runningSince != nil }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func resume(at date: Date = Date()) {
        guard runningSince == nil else { return }
        runningSince = date
    }

    mutating func pause(at date: Date = Date()) {
        guard let runningSince else { return }
        accumulated += max(0, date.timeIntervalSince(runningSince))
        self.runningSince = nil
    }
}

/// Where a reading-speed test is: intro → countdown → reading → quiz → result.
/// Shared by onboarding and `SpeedTestView`, and driven with `withAnimation` so stages crossfade.
struct SpeedTestProgress: Equatable {
    enum Stage: Hashable {
        case intro, countdown, reading, quiz, result
    }

    var stage: Stage
    var passage: SpeedTestPassage
    var clock: SpeedTestClock
    /// Chosen answer index per question, in order. The current question is `answers.count`.
    var answers: [Int]
    var result: SpeedTestResult?
    /// The WPM count-up has played for this result (going back to it shouldn't replay it).
    var hasRevealedResult: Bool

    /// Faster than this reads as skimming; the reader is asked before we believe it.
    static let skimmingWPM: Double = 900
    /// The pace of the staged sample result (screenshots and previews).
    static let samplePace: Double = 262

    init(passage: SpeedTestPassage, stage: Stage = .intro) {
        self.stage = stage
        self.passage = passage
        self.clock = SpeedTestClock()
        self.answers = []
        self.result = nil
        self.hasRevealedResult = false
    }

    /// Reading time that gives `samplePace` for `passage`.
    static func sampleSeconds(for passage: SpeedTestPassage) -> TimeInterval {
        Double(max(passage.wordCount, 1)) / samplePace * 60
    }

    /// A believable full-marks result for staged screens.
    static func sampleResult(for passage: SpeedTestPassage, date: Date = Date()) -> SpeedTestResult {
        let total = passage.questions.count
        return SpeedTestResult(
            date: date,
            passageID: passage.id,
            words: passage.wordCount,
            seconds: sampleSeconds(for: passage),
            correct: total,
            total: total
        )
    }

    mutating func beginCountdown() {
        clock = SpeedTestClock()
        answers = []
        result = nil
        stage = .countdown
    }

    /// The passage appears and the clock starts.
    mutating func startReading(at date: Date = Date()) {
        clock = SpeedTestClock(runningSince: date)
        stage = .reading
    }

    /// True when "I've finished" comes so soon that it can only be skimming.
    func readsImplausiblyFast(at date: Date = Date()) -> Bool {
        let seconds = clock.elapsed(at: date)
        guard seconds > 0 else { return true }
        return ReadingSpeed.wpm(words: passage.wordCount, seconds: seconds) > Self.skimmingWPM
    }

    /// Stops the clock and moves on to the questions.
    mutating func finishReading(at date: Date = Date()) {
        clock.pause(at: date)
        answers = []
        stage = .quiz
    }

    /// Scores the answers and shows the result.
    @discardableResult
    mutating func completeQuiz(at date: Date = Date()) -> SpeedTestResult {
        let total = passage.questions.count
        let correct = zip(answers, passage.questions).filter { $0.0 == $0.1.answerIndex }.count
        let made = SpeedTestResult(
            date: date,
            passageID: passage.id,
            words: passage.wordCount,
            seconds: max(1, clock.elapsed(at: date)),
            correct: correct,
            total: total
        )
        result = made
        hasRevealedResult = false
        stage = .result
        return made
    }

    /// Starts over with a fresh passage (Retake).
    mutating func restart(with passage: SpeedTestPassage) {
        self = SpeedTestProgress(passage: passage)
    }

    /// One step back inside the test: a question back, or from the countdown, passage or first
    /// question to the intro. Does nothing at the intro or the result.
    mutating func stepBack() {
        switch stage {
        case .intro, .result:
            break
        case .countdown, .reading:
            clock = SpeedTestClock()
            stage = .intro
        case .quiz:
            if answers.isEmpty {
                clock = SpeedTestClock()
                stage = .intro
            } else {
                answers.removeLast()
            }
        }
    }
}
