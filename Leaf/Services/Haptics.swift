import CoreHaptics
import UIKit

/// Named haptic moments. Simple ones use UIKit feedback generators; signature ones are Core Haptics patterns
/// (DESIGN.md §8).
enum HapticMoment {
    case pageTurn, bookFinished, countdownBeat, sessionStart, sessionEnd, dialDetent, goalReached, reorderLift, reorderDrop
    /// The pot is ready: two soft clinks, cup on saucer.
    case teaReady
    /// A card kept in the swipe deck: heavier than the tick of a pass, with a short settle.
    case deckKeep
    /// "Start now" from the swipe deck: a rising double tap.
    case deckStart
    /// A scrub control locking onto a meaningful value (your goal, a round hour): a firm click with a small echo.
    case magnetSnap
    /// A scrub control pushing against its end: a dull knock.
    case boundsHit
}

@MainActor
final class Haptics {
    static let shared = Haptics()

    /// Follows the reader's Settings → Feel choice. Set by the app whenever preferences change.
    var level: HapticsLevel = .full

    private var engine: CHHapticEngine?
    /// The continuous buzz that follows a ribbon's stretch while it is dragged.
    private var stretchPlayer: CHHapticAdvancedPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    /// How heavy a book feels, 0…1, from its page count: long books land heavier.
    static func heft(pages: Int) -> Double {
        min(1, max(0, Double(pages - 150) / 650))
    }

    func prepare() {
        guard level != .off else { return }
        selectionGenerator.prepare()
        lightGenerator.prepare()
        guard supportsHaptics, level == .full else { return }
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
        }
        try? engine?.start()
    }

    // MARK: Simple feedback

    func selection() {
        guard level != .off else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    func tap() {
        guard level != .off else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
    }

    func soft(_ intensity: CGFloat = 0.7) {
        guard level != .off else { return }
        softGenerator.impactOccurred(intensity: intensity)
    }

    func rigid(_ intensity: CGFloat = 0.8) {
        guard level != .off else { return }
        rigidGenerator.impactOccurred(intensity: intensity)
    }

    func press() {
        guard level != .off else { return }
        mediumGenerator.impactOccurred(intensity: 0.6)
    }

    func success() { notify(.success) }
    func warning() { notify(.warning) }
    func error() { notify(.error) }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard level != .off else { return }
        notificationGenerator.notificationOccurred(type)
    }

    // MARK: Signature moments

    /// Plays a signature pattern. `heft` (0…1, see `heft(pages:)`) makes long books feel heavier.
    func play(_ moment: HapticMoment, heft: Double = 0) {
        guard level != .off else { return }
        let h = Float(min(1, max(0, heft)))
        playPattern(events: Self.events(for: moment, heft: h), curves: Self.curves(for: moment)) { [weak self] in
            self?.fallback(for: moment)
        }
    }

    /// A quick riffle of `count` ticks (max 6) when plan dates move: crisp if they moved earlier, dull if later.
    func riffle(count: Int, earlier: Bool) {
        guard level != .off, count > 0 else { return }
        let n = min(6, count)
        let events = (0..<n).map { i in
            Self.transient(0.04 * Double(i), intensity: 0.28, sharpness: earlier ? 0.8 : 0.3)
        }
        playPattern(events: events, curves: []) { [weak self] in self?.selection() }
    }

    // MARK: Scrubbing

    /// Plays what a `ScrubModel` asked for. Ticks are single transients shaped by the model (lighter and softer as the
    /// finger speeds up); a snap onto a magnet is `magnetSnap`, and the end of the range is `boundsHit`, both scaled by
    /// the event's intensity.
    func scrub(_ event: ScrubHapticEvent) {
        guard level != .off else { return }
        let intensity = min(1, max(0, event.intensity))
        switch event.kind {
        case .tick, .majorTick:
            let transient = Self.transient(0, intensity: Float(intensity), sharpness: Float(min(1, max(0, event.sharpness))))
            playPattern(events: [transient], curves: []) { [weak self] in
                if event.kind == .majorTick { self?.rigid(CGFloat(0.4 + 0.5 * intensity)) } else { self?.selection() }
            }
        case .magnetSnap:
            play(.magnetSnap, heft: intensity)
        case .boundsHit:
            play(.boundsHit, heft: intensity)
        }
    }

    // MARK: Stretch

    /// Starts a soft continuous buzz for dragging the ribbon; `updateStretch` sets how strong it is. Silent at 0.
    func beginStretch() {
        guard level == .full, supportsHaptics else { return }
        if engine == nil { prepare() }
        guard let engine, stretchPlayer == nil else { return }
        let buzz = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15),
        ], relativeTime: 0, duration: 30)
        do {
            let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [buzz], parameters: []))
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            try player.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: 0, relativeTime: 0)], atTime: CHHapticTimeImmediate)
            stretchPlayer = player
        } catch {
            stretchPlayer = nil
        }
    }

    /// 0 (slack) to 1 (pulled hard): the buzz follows it.
    func updateStretch(_ amount: Double) {
        guard let stretchPlayer else { return }
        let value = Float(min(1, max(0, amount)))
        try? stretchPlayer.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: value, relativeTime: 0)], atTime: CHHapticTimeImmediate)
    }

    func endStretch() {
        try? stretchPlayer?.stop(atTime: CHHapticTimeImmediate)
        stretchPlayer = nil
    }

    private func playPattern(events: [CHHapticEvent], curves: [CHHapticParameterCurve], fallback: () -> Void) {
        guard level == .full, supportsHaptics else { return fallback() }
        if engine == nil { prepare() }
        guard let engine else { return fallback() }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    private func fallback(for moment: HapticMoment) {
        switch moment {
        case .bookFinished, .goalReached: success()
        case .dialDetent: selection()
        case .reorderLift, .sessionStart: press()
        case .reorderDrop, .countdownBeat, .sessionEnd, .pageTurn, .teaReady: soft()
        case .deckKeep: rigid(0.7)
        case .deckStart: press()
        case .magnetSnap: rigid(0.9)
        case .boundsHit: soft(0.8)
        }
    }

    private static func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private static func continuous(_ time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time, duration: duration)
    }

    private static func curve(_ points: [(TimeInterval, Float)]) -> CHHapticParameterCurve {
        CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: points.map { CHHapticParameterCurve.ControlPoint(relativeTime: $0.0, value: $0.1) },
            relativeTime: 0
        )
    }

    static func events(for moment: HapticMoment, heft h: Float = 0) -> [CHHapticEvent] {
        switch moment {
        case .pageTurn:
            return [continuous(0, duration: 0.16, intensity: 0.35, sharpness: 0.15), transient(0.17, intensity: 0.55, sharpness: 0.35)]
        case .bookFinished:
            // Three rising taps, a warm swell, then a cover closing — heavier for long books.
            return [
                transient(0, intensity: 0.45, sharpness: 0.4),
                transient(0.11, intensity: 0.6, sharpness: 0.5),
                transient(0.22, intensity: 0.8, sharpness: 0.6),
                continuous(0.30, duration: 0.45, intensity: 0.5, sharpness: 0.2),
                transient(0.80, intensity: 0.8 + 0.2 * h, sharpness: 0.3),
                transient(0.92, intensity: 0.3, sharpness: 0.2),
            ]
        case .countdownBeat:
            return [transient(0, intensity: 0.7, sharpness: 0.2), transient(0.12, intensity: 0.45, sharpness: 0.15)]
        case .sessionStart:
            return [transient(0, intensity: 0.6, sharpness: 0.5), continuous(0.05, duration: 0.25, intensity: 0.3, sharpness: 0.1)]
        case .sessionEnd:
            return [continuous(0, duration: 0.2, intensity: 0.35, sharpness: 0.1), transient(0.22, intensity: 0.75, sharpness: 0.3)]
        case .dialDetent:
            return [transient(0, intensity: 0.45, sharpness: 0.8)]
        case .goalReached:
            return [transient(0, intensity: 0.6, sharpness: 0.4), transient(0.15, intensity: 0.9, sharpness: 0.55), continuous(0.2, duration: 0.35, intensity: 0.4, sharpness: 0.15)]
        case .reorderLift:
            return [transient(0, intensity: 0.35 + 0.3 * h, sharpness: 0.5), continuous(0.02, duration: 0.12, intensity: 0.2, sharpness: 0.1)]
        case .reorderDrop:
            return [transient(0, intensity: 0.45 + 0.4 * h, sharpness: 0.3), transient(0.06, intensity: 0.25, sharpness: 0.2)]
        case .teaReady:
            return [transient(0, intensity: 0.5, sharpness: 0.55), transient(0.16, intensity: 0.32, sharpness: 0.45)]
        case .deckKeep:
            return [transient(0, intensity: 0.7, sharpness: 0.45), continuous(0.03, duration: 0.12, intensity: 0.25, sharpness: 0.1)]
        case .deckStart:
            return [transient(0, intensity: 0.55, sharpness: 0.5), transient(0.1, intensity: 0.85, sharpness: 0.6)]
        case .magnetSnap:
            return [transient(0, intensity: 0.9 + 0.1 * h, sharpness: 0.85), transient(0.045, intensity: 0.35, sharpness: 0.6)]
        case .boundsHit:
            return [transient(0, intensity: 0.5 + 0.5 * h, sharpness: 0.22)]
        }
    }

    static func curves(for moment: HapticMoment) -> [CHHapticParameterCurve] {
        switch moment {
        case .pageTurn: return [curve([(0, 0.2), (0.08, 1), (0.16, 0.1)])]
        case .bookFinished: return [curve([(0.30, 0.2), (0.55, 1), (0.75, 0.15)])]
        case .reorderLift: return [curve([(0.02, 1), (0.14, 0)])]
        case .deckKeep: return [curve([(0.03, 1), (0.15, 0)])]
        default: return []
        }
    }
}
