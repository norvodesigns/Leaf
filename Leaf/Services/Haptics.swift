import CoreHaptics
import UIKit

/// Named haptic moments. Simple ones use UIKit feedback generators; signature ones are Core Haptics patterns.
enum HapticMoment {
    case pageTurn, bookFinished, countdownBeat, sessionStart, sessionEnd, dialDetent, goalReached, reorderLift, reorderDrop
}

@MainActor
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    func prepare() {
        selectionGenerator.prepare()
        lightGenerator.prepare()
        guard supportsHaptics else { return }
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

    func selection() { selectionGenerator.selectionChanged(); selectionGenerator.prepare() }
    func tap() { lightGenerator.impactOccurred(); lightGenerator.prepare() }
    func soft(intensity: CGFloat = 0.7) { softGenerator.impactOccurred(intensity: intensity) }
    func rigid(intensity: CGFloat = 0.8) { rigidGenerator.impactOccurred(intensity: intensity) }
    func press() { mediumGenerator.impactOccurred(intensity: 0.6) }
    func success() { notificationGenerator.notificationOccurred(.success) }
    func warning() { notificationGenerator.notificationOccurred(.warning) }
    func error() { notificationGenerator.notificationOccurred(.error) }

    // MARK: Signature moments

    func play(_ moment: HapticMoment) {
        guard supportsHaptics, let engine else { return fallback(for: moment) }
        do {
            let pattern = try CHHapticPattern(events: Self.events(for: moment), parameterCurves: Self.curves(for: moment))
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(for: moment)
        }
    }

    private func fallback(for moment: HapticMoment) {
        switch moment {
        case .bookFinished, .goalReached: success()
        case .dialDetent: selection()
        case .reorderLift, .sessionStart: press()
        case .reorderDrop, .countdownBeat, .sessionEnd, .pageTurn: soft()
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

    static func events(for moment: HapticMoment) -> [CHHapticEvent] {
        switch moment {
        case .pageTurn:
            // A soft swish of paper ending in a light settle.
            return [continuous(0, duration: 0.16, intensity: 0.35, sharpness: 0.15), transient(0.17, intensity: 0.55, sharpness: 0.35)]
        case .bookFinished:
            // Three rising taps, a warm swell, then a closing thump like a cover shutting.
            return [
                transient(0, intensity: 0.45, sharpness: 0.4),
                transient(0.11, intensity: 0.6, sharpness: 0.5),
                transient(0.22, intensity: 0.8, sharpness: 0.6),
                continuous(0.3, duration: 0.45, intensity: 0.5, sharpness: 0.2),
                transient(0.8, intensity: 1.0, sharpness: 0.3),
            ]
        case .countdownBeat:
            // A heartbeat: lub-dub.
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
            return [transient(0, intensity: 0.7, sharpness: 0.6)]
        case .reorderDrop:
            return [transient(0, intensity: 0.5, sharpness: 0.25)]
        }
    }

    static func curves(for moment: HapticMoment) -> [CHHapticParameterCurve] {
        switch moment {
        case .pageTurn:
            return [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0.2), .init(relativeTime: 0.08, value: 1), .init(relativeTime: 0.16, value: 0.1),
            ], relativeTime: 0)]
        case .bookFinished:
            return [CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0.3, value: 0.2), .init(relativeTime: 0.55, value: 1), .init(relativeTime: 0.75, value: 0.15),
            ], relativeTime: 0)]
        default:
            return []
        }
    }
}
