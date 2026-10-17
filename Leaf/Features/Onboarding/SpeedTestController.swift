import SwiftUI

/// Runs one reading-speed test: intro, countdown, reading, quiz, result. Onboarding and the
/// Settings retake both drive their screens from one of these, so the timing, the quiz and the
/// skimming check behave identically in both places.
@MainActor
@Observable
final class SpeedTestController {
    var progress: SpeedTestProgress
    /// The answer just tapped on the current question. The quiz moves on a beat later.
    var pendingAnswer: Int?
    /// "I've finished" came too soon to be reading; the reader is asked before we believe it.
    var showsSkimWarning = false

    @ObservationIgnored private var advanceTask: Task<Void, Never>?

    /// - Parameters:
    ///   - stage: where to begin. Anything past `.intro` is a staged state for screenshots, previews
    ///     and returning to an earlier step.
    ///   - result: for `.result`, the result to show. Without one, a sample at `samplePace` is staged.
    init(passage: SpeedTestPassage, stage: SpeedTestProgress.Stage = .intro, result: SpeedTestResult? = nil, now: Date = Date()) {
        var start = SpeedTestProgress(passage: passage)
        switch stage {
        case .intro:
            break
        case .countdown:
            start.beginCountdown()
        case .reading:
            start.beginCountdown()
            start.startReading(at: now)
        case .quiz:
            start.beginCountdown()
            start.startReading(at: now.addingTimeInterval(-SpeedTestProgress.sampleSeconds(for: passage)))
            start.finishReading(at: now)
        case .result:
            start.result = result ?? SpeedTestProgress.sampleResult(for: passage, date: now)
            start.stage = .result
        }
        self.progress = start
    }

    // MARK: - Reading the state

    var stage: SpeedTestProgress.Stage { progress.stage }
    var passage: SpeedTestPassage { progress.passage }
    var result: SpeedTestResult? { progress.result }

    /// The question being asked, if any.
    var currentQuestion: ComprehensionQuestion? {
        let questions = progress.passage.questions
        let index = progress.answers.count
        return questions.indices.contains(index) ? questions[index] : nil
    }

    /// True in the countdown, the passage and the questions: places where Back means one step back
    /// inside the test. The intro and the result have no step back.
    var canStepBack: Bool {
        switch progress.stage {
        case .countdown, .reading, .quiz: true
        case .intro, .result: false
        }
    }

    // MARK: - Moving through the test

    func beginCountdown() {
        guard progress.stage == .intro else { return }
        progress.beginCountdown()
    }

    /// The countdown reached zero: the passage appears and the clock starts.
    func startReading() {
        guard progress.stage == .countdown else { return }
        progress.startReading()
    }

    /// "I've finished": stops the clock, unless it came too fast to be reading.
    func finishReading() {
        guard progress.stage == .reading else { return }
        if progress.readsImplausiblyFast() {
            progress.clock.pause()
            showsSkimWarning = true
        } else {
            confirmFinishReading()
        }
    }

    /// The reader says they did read it (or it was plausible all along): on to the questions.
    func confirmFinishReading() {
        guard progress.stage == .reading else { return }
        progress.finishReading()
        if progress.passage.questions.isEmpty {
            progress.completeQuiz()
        }
    }

    /// "Read it again": back through the countdown with a fresh clock.
    func readAgain() {
        guard progress.stage == .reading else { return }
        progress.beginCountdown()
    }

    /// Taps an answer: a selection tick, the caret slides in, and 0.35 s later the next question.
    func choose(_ index: Int) {
        guard progress.stage == .quiz, pendingAnswer == nil,
              let question = currentQuestion, question.choices.indices.contains(index) else { return }
        Haptics.shared.selection()
        pendingAnswer = index
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.commitAnswer(index)
        }
    }

    private func commitAnswer(_ index: Int) {
        guard progress.stage == .quiz else { return }
        progress.answers.append(index)
        if progress.answers.count >= progress.passage.questions.count {
            // The last answer keeps its caret while the quiz crossfades into the result.
            progress.completeQuiz()
        } else {
            pendingAnswer = nil
        }
    }

    /// One step back inside the test. Check `canStepBack` first.
    func stepBack() {
        cancelPending()
        progress.stepBack()
    }

    /// Starts over from the intro with a different passage ("Retake").
    func retake() {
        cancelPending()
        progress.restart(with: SpeedTestPassages.passage(after: progress.passage.id))
    }

    /// Back to the intro with the same passage (returning from a step after a skipped test).
    func showIntro() {
        cancelPending()
        progress = SpeedTestProgress(passage: progress.passage)
    }

    /// The count-up has played; going back to the result shouldn't replay it.
    func markResultRevealed() {
        progress.hasRevealedResult = true
    }

    /// The clock only runs while the app is in front: a phone call mid-passage isn't reading.
    func setClockRunning(_ isRunning: Bool) {
        guard progress.stage == .reading, !showsSkimWarning else { return }
        if isRunning {
            progress.clock.resume()
        } else {
            progress.clock.pause()
        }
    }

    private func cancelPending() {
        advanceTask?.cancel()
        advanceTask = nil
        pendingAnswer = nil
        showsSkimWarning = false
    }

    // MARK: - Buttons

    /// The buttons for the current stage, shared by onboarding and the retake.
    /// - Parameters:
    ///   - resultTitle: the result's primary button ("Continue" in onboarding).
    ///   - introSecondary: an optional quiet action under "I'm ready".
    ///   - onResult: what the result's primary button does.
    func actions(
        resultTitle: String,
        introSecondary: OnboardingAction? = nil,
        onResult: @escaping () -> Void
    ) -> (primary: OnboardingAction?, secondary: OnboardingAction?) {
        switch progress.stage {
        case .intro:
            return (OnboardingAction("I’m ready") { [weak self] in self?.beginCountdown() }, introSecondary)
        case .countdown, .quiz:
            return (nil, nil)
        case .reading:
            return (OnboardingAction("I’ve finished") { [weak self] in self?.finishReading() }, nil)
        case .result:
            return (
                OnboardingAction(resultTitle, perform: onResult),
                OnboardingAction("Retake") { [weak self] in self?.retake() }
            )
        }
    }
}
