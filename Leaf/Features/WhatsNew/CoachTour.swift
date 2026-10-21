import SwiftUI

/// The tour ("A quick look around"): coach marks on the real screens, one at a time, on the first visit to each part
/// of the app while the tour runs. It starts at the end of onboarding, from What's new or from Settings ("Replay the
/// tour"), never repeats unless asked, and stops for good when skipped. Progress is kept per step on this device;
/// screenshot runs keep it in memory only.
@MainActor
@Observable
final class CoachTour {
    static let shared = CoachTour()

    private(set) var progress: TourProgress
    let steps = TourSteps.all

    private let persists: Bool
    private static let key = "leaf.tour.progress"

    private init() {
        persists = !LaunchOptions.current.isScripted
        if persists, let data = UserDefaults.standard.data(forKey: CoachTour.key),
           let saved = try? JSONDecoder().decode(TourProgress.self, from: data) {
            progress = saved
        } else {
            progress = TourProgress()
        }
    }

    var isRunning: Bool { progress.isRunning }

    func start() {
        progress.start()
        save()
    }

    /// Screenshots: the tour from `step` on in its area.
    func stage(from step: String) {
        progress.start()
        for earlier in steps {
            if earlier.id == step { break }
            progress.markSeen(earlier.id)
        }
    }

    func skip() {
        progress.skip()
        save()
    }

    func advance(past id: String) {
        progress.advance(past: id, steps: steps)
        save()
    }

    func finishArea(_ area: TourArea) {
        for step in steps where step.area == area { progress.markSeen(step.id) }
        progress.advance(past: steps.first { $0.area == area }?.id ?? "", steps: steps)
        save()
    }

    func next(in area: TourArea, available: Set<String>) -> TourStep? {
        progress.nextStep(in: area, steps: steps, available: available)
    }

    func remaining(in area: TourArea) -> [TourStep] {
        progress.remaining(in: area, steps: steps)
    }

    /// "2 of 4" within the step's area.
    func position(of step: TourStep) -> String {
        let inArea = steps.filter { $0.area == step.area }
        let index = (inArea.firstIndex(of: step) ?? 0) + 1
        return "\(index) of \(inArea.count)"
    }

    func isLast(_ step: TourStep) -> Bool {
        steps.last { $0.area == step.area } == step
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: CoachTour.key)
    }
}

/// Shows the tour's coach marks for `area` over this screen: the next step whose target is on screen (or that can
/// float), one at a time. With VoiceOver on, the area's steps come as one list instead.
private struct CoachMarkHost: ViewModifier {
    let area: TourArea
    var bottomClearance: CGFloat = 150

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsList = false

    private var tour: CoachTour { CoachTour.shared }

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(CoachMarkAnchors.self) { anchors in
                if !voiceOver {
                    GeometryReader { proxy in
                        let visible = CoachMarkHost.visible(anchors, in: proxy)
                        if let step = tour.next(in: area, available: Set(visible.keys)) {
                            CoachMarkPlacement(
                                target: visible[step.id],
                                container: proxy.size,
                                bottomClearance: bottomClearance
                            ) { arrow, arrowX in
                                CoachMarkCallout(
                                    title: step.title,
                                    text: step.text,
                                    position: tour.position(of: step),
                                    isLast: tour.isLast(step),
                                    arrow: arrow,
                                    arrowX: arrowX,
                                    next: { advance(step) },
                                    skip: skip
                                )
                            }
                            .id(step.id)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
            }
            .onAppear {
                if voiceOver && !tour.remaining(in: area).isEmpty { showsList = true }
            }
            .sheet(isPresented: $showsList) {
                CoachMarkList(
                    heading: "A quick look around",
                    steps: tour.remaining(in: area),
                    done: {
                        tour.finishArea(area)
                        showsList = false
                    },
                    skip: {
                        skip()
                        showsList = false
                    }
                )
            }
    }

    /// The targets actually on screen (with room for a callout), in this view's coordinates. A target scrolled out
    /// of sight waits until it comes back.
    static func visible(_ anchors: [String: Anchor<CGRect>], in proxy: GeometryProxy) -> [String: CGRect] {
        let screen = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 0, dy: 40)
        var found: [String: CGRect] = [:]
        for (id, anchor) in anchors {
            let rect = proxy[anchor]
            if screen.intersects(rect) && rect.minY > 20 && rect.maxY < proxy.size.height - 60 { found[id] = rect }
        }
        return found
    }

    private func advance(_ step: TourStep) {
        Haptics.shared.selection()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            tour.advance(past: step.id)
        }
    }

    private func skip() {
        Haptics.shared.tap()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            tour.skip()
        }
    }
}

extension View {
    /// The tour's coach marks for `area`, over this screen. Mark targets inside it with `coachMarkAnchor(_:)`.
    func coachMarks(_ area: TourArea, bottomClearance: CGFloat = 150) -> some View {
        modifier(CoachMarkHost(area: area, bottomClearance: bottomClearance))
    }
}
