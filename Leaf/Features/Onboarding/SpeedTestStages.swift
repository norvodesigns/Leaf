import SwiftUI

/// The body of whichever stage the test is in. Onboarding and the retake both put this inside their
/// own frame; it also hosts the "that was quick" check.
struct SpeedTestStageBody: View {
    @Bindable var controller: SpeedTestController
    var isRetake: Bool

    init(controller: SpeedTestController, isRetake: Bool = false) {
        self.controller = controller
        self.isRetake = isRetake
    }

    var body: some View {
        stage
            .alert("That was quick", isPresented: $controller.showsSkimWarning) {
                Button("Read it again") {
                    controller.readAgain()
                }
                Button("I did read it", role: .cancel) {
                    controller.confirmFinishReading()
                }
            } message: {
                Text("That’s faster than most people can take a passage in. Give it another go at your usual pace, or carry on if you did read every line.")
            }
    }

    @ViewBuilder
    private var stage: some View {
        switch controller.progress.stage {
        case .intro:
            SpeedTestIntroView(isRetake: isRetake)
        case .countdown:
            SpeedTestCountdownView(controller: controller)
        case .reading:
            SpeedTestReadingView(controller: controller)
        case .quiz:
            SpeedTestQuizView(controller: controller)
        case .result:
            SpeedTestResultView(controller: controller)
        }
    }
}

// MARK: - Intro

/// "First, a short read." and what to expect.
struct SpeedTestIntroView: View {
    var isRetake: Bool

    init(isRetake: Bool = false) {
        self.isRetake = isRetake
    }

    var body: some View {
        OnboardingPage {
            VStack(spacing: Space.xxl) {
                OnboardingHeading(
                    title: isRetake ? "A fresh read." : "First, a short read.",
                    message: isRetake
                        ? "A different passage this time. Read at your usual pace — there’s no clock on screen."
                        : "About two minutes. Read at your usual pace — there’s no clock on screen."
                )
                VStack(spacing: 0) {
                    Hairline()
                    SpeedTestExpectationRow(number: 1, text: "Read a short passage, silently.")
                    Hairline()
                    SpeedTestExpectationRow(number: 2, text: "Answer three quick questions.")
                    Hairline()
                    SpeedTestExpectationRow(number: 3, text: "See your pace, and what it means for your books.")
                    Hairline()
                }
            }
        }
    }
}

private struct SpeedTestExpectationRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            IndexNumeral(number)
            Text(text)
                .leafStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Space.l)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Countdown

/// 3, 2, 1 in `countdown` with a `countdownBeat` on each numeral, then the passage.
struct SpeedTestCountdownView: View {
    let controller: SpeedTestController

    @State private var value = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.l) {
            Eyebrow("Get ready")
            ZStack {
                Text(verbatim: "\(value)")
                    .leafStyle(.countdown)
                    .id(value)
                    .transition(Motion.transition(.countdownNumeral, reduceMotion: reduceMotion))
            }
            .frame(height: 190)
            Text("Begin reading when the page appears.")
                .leafStyle(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.resolved(.easeOut(duration: 0.28), reduceMotion: reduceMotion), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Starting in \(value)")
        .accessibilityAddTraits(.updatesFrequently)
        .task {
            await runCountdown()
        }
    }

    private func runCountdown() async {
        for number in [3, 2, 1] {
            value = number
            Haptics.shared.play(.countdownBeat)
            try? await Task.sleep(for: .milliseconds(900))
            if Task.isCancelled { return }
        }
        controller.startReading()
    }
}

// MARK: - Reading

/// The passage, typeset for reading. The first four words are in small caps, and a 1 px `ribbon`
/// rule in the left margin grows as the reader scrolls. There is no clock on screen; the timing
/// runs from the moment this appears to "I've finished".
struct SpeedTestReadingView: View {
    let controller: SpeedTestController

    /// How far down the passage the reader has scrolled, 0…1.
    @State private var scrolled: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    /// The rule starts as a short mark so the margin is never empty.
    private let ruleMinimum: CGFloat = 28
    private let textLeading: CGFloat = 36

    var body: some View {
        let passage = controller.progress.passage
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    header(passage)
                    ForEach(Array(passage.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                        paragraphView(paragraph, leadsWithSmallCaps: index == 0)
                    }
                    Text("❦")
                        .leafStyle(.index, color: .inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s)
                        .accessibilityHidden(true)
                }
                .padding(.leading, textLeading)
                .padding(.trailing, Space.margin)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onScrollGeometryChange(for: Double.self) { geometry in
                let insets = geometry.contentInsets.top + geometry.contentInsets.bottom
                let scrollable = Double(geometry.contentSize.height + insets - geometry.containerSize.height)
                guard scrollable > 1 else { return 0.0 }
                let offset = Double(geometry.contentOffset.y + geometry.contentInsets.top)
                let fraction = min(1.0, max(0.0, offset / scrollable))
                return (fraction * 200).rounded() / 200
            } action: { _, newValue in
                scrolled = newValue
            }
            .overlay(alignment: .topLeading) {
                Hairline(color: .ribbon, axis: .vertical)
                    .frame(height: ruleMinimum + (proxy.size.height - ruleMinimum) * CGFloat(scrolled))
                    .padding(.leading, Space.margin)
                    .padding(.top, Space.l)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: controller.setClockRunning(true)
            case .background: controller.setClockRunning(false)
            default: break
            }
        }
    }

    private func header(_ passage: SpeedTestPassage) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow(passage.kicker)
            Text(passage.title)
                .leafStyle(.masthead)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Written for Leaf · \(passage.wordCount) words")
                .leafStyle(.caption)
        }
        .padding(.bottom, Space.s)
    }

    private func paragraphView(_ text: String, leadsWithSmallCaps: Bool) -> some View {
        Group {
            if leadsWithSmallCaps {
                let parts = Self.splitLead(text, words: 4)
                Text("\(Text(parts.lead).font(LeafType.passage.lowercaseSmallCaps()))\(Text(parts.rest))")
            } else {
                Text(text)
            }
        }
        .leafStyle(.passage)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Splits `text` after its first `words` words, keeping the space that follows with the rest.
    static func splitLead(_ text: String, words: Int) -> (lead: String, rest: String) {
        var seen = 0
        var inWord = false
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == " " {
                if inWord {
                    seen += 1
                    inWord = false
                    if seen == words { break }
                }
            } else {
                inWord = true
            }
            index = text.index(after: index)
        }
        return (String(text[..<index]), String(text[index...]))
    }
}

// MARK: - Quiz

/// "QUESTION 2 OF 3" and four hairline rows lettered a to d in small caps. A tap plays `selection`,
/// a `ribbon` caret slides in, and the next question follows after 0.35 s.
struct SpeedTestQuizView: View {
    let controller: SpeedTestController

    private static let letters = ["a", "b", "c", "d", "e", "f"]

    var body: some View {
        let questions = controller.passage.questions
        // After the last answer the stage moves on, so keep showing the last question while it fades.
        let index = min(controller.progress.answers.count, max(questions.count - 1, 0))
        OnboardingPage(alignment: .topLeading) {
            if questions.indices.contains(index) {
                let question = questions[index]
                VStack(alignment: .leading, spacing: Space.xl) {
                    Eyebrow("Question \(index + 1) of \(questions.count)")
                    Text(question.prompt)
                        .leafStyle(.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(Array(question.choices.enumerated()), id: \.offset) { choiceIndex, choice in
                            SpeedTestChoiceRow(
                                letter: choiceIndex < Self.letters.count ? Self.letters[choiceIndex] : "",
                                text: choice,
                                isSelected: controller.pendingAnswer == choiceIndex,
                                isDimmed: controller.pendingAnswer != nil && controller.pendingAnswer != choiceIndex
                            ) {
                                controller.choose(choiceIndex)
                            }
                            Hairline()
                        }
                    }
                }
                .id(index)
                .transition(.opacity)
            }
        }
        .leafAnimation(.easeInOut(duration: 0.25), value: index)
    }
}

private struct SpeedTestChoiceRow: View {
    let letter: String
    let text: String
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                ZStack {
                    if isSelected {
                        SpeedTestCaret()
                            .stroke(Color.ribbon, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 9, height: 6)
                            .transition(.asymmetric(insertion: .offset(x: -8).combined(with: .opacity), removal: .opacity))
                    }
                }
                .frame(width: 14, alignment: .leading)
                Text(letter)
                    .leafStyle(.author, color: isSelected ? Color.ink : Color.inkTertiary)
                    .frame(width: 22, alignment: .leading)
                Text(text)
                    .leafStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Space.m)
            .frame(minHeight: 56)
            .contentShape(.rect)
            .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(.pressable)
        .leafAnimation(Motion.glass, value: isSelected)
        .leafAnimation(.easeOut(duration: 0.2), value: isDimmed)
        .accessibilityLabel("\(letter.uppercased()). \(text)")
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// The insertion caret: a small `^` that stands on the baseline.
private struct SpeedTestCaret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
