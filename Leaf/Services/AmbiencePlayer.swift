#if canImport(AVFoundation)
import AVFoundation
import Observation
import UIKit

/// How Leaf's sounds share the phone's audio session.
///
/// Ambience uses `.playback`, which (unlike `.ambient`) keeps playing with the silent switch on. That is deliberate:
/// someone who flips the switch to silence notifications has still asked, by tapping play, for the rain. Both
/// categories use `.mixWithOthers`, so the reader's own music or podcast keeps playing underneath.
///
/// The little cue sounds (kettle, pour, chime, page) are incidental, so they follow the silent switch unless
/// ambience is already playing.
enum LeafAudioSession {
    /// Sets the category and activates the session. Returns false if iOS refuses (for instance during a call).
    @discardableResult
    static func activate(overridingSilentSwitch: Bool) -> Bool {
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = overridingSilentSwitch ? .playback : .ambient
        do {
            if session.category != category || !session.categoryOptions.contains(.mixWithOthers) {
                try session.setCategory(category, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }
}

/// Plays one procedural ambience (rain, fireplace, kettle, cafe or library) at a time, made on the fly by
/// `AmbienceSynth`: no audio files, nothing to license, nothing to download.
///
/// Ids are the ones in `AmbienceCatalog` and `ReadingPreferences.ambienceID`. Anything else, including "none", stops
/// the sound. The player pauses itself when a call or alarm interrupts and picks up again when it ends; it pauses
/// when headphones are unplugged and waits to be asked before playing out loud. (Named `AmbiencePlayer` because
/// `Ambience` is the catalog entry type.)
///
/// The synth runs on the audio thread and is steered only through `fade(to:over:)`, which never blocks it.
@MainActor
@Observable
final class AmbiencePlayer {
    static let shared = AmbiencePlayer()

    /// The id of the ambience chosen, or nil when nothing is playing (or it is fading out after `stop`).
    private(set) var currentID: String?
    /// True while the ambience is actually sounding. False when stopped, interrupted or paused.
    private(set) var isPlaying = false
    /// The last volume set, 0 to 1.
    private(set) var volume: Float = 0.5

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var sourceNode: AVAudioSourceNode?
    @ObservationIgnored private var synth: AmbienceSynth?
    /// Whether the reader wants sound. Survives an interruption (so it can resume) but not a headphone unplug.
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Gives every start its own (but repeatable) noise.
    @ObservationIgnored private var startCount: UInt64 = 0

    private init() {}

    // MARK: Controls

    /// Starts `id` at `volume` (0 to 1), fading in over `fadeIn` seconds. If another ambience is playing it fades out
    /// first; if this one is already playing only the volume changes.
    func play(_ id: String, volume: Float = 0.5, fadeIn: TimeInterval = 2) {
        guard let recipe = AmbienceRecipe(id: id) else {
            stop(fadeOut: 0.5)
            return
        }
        self.volume = Self.clamped(volume)
        transitionTask?.cancel()
        transitionTask = nil
        installObserversIfNeeded()
        wantsPlayback = true

        if currentID == id, synth != nil {
            resumeEngine()
            return
        }
        currentID = id
        if let outgoing = synth, engine.isRunning {
            outgoing.fade(to: 0, over: 0.25)
            transitionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.start(recipe, fadeIn: fadeIn)
            }
        } else {
            start(recipe, fadeIn: fadeIn)
        }
    }

    /// Fades out over `fadeOut` seconds, then releases the audio engine.
    func stop(fadeOut: TimeInterval = 1.5) {
        transitionTask?.cancel()
        transitionTask = nil
        wantsPlayback = false
        currentID = nil
        isPlaying = false
        guard let synth else { return }
        guard fadeOut > 0, engine.isRunning else {
            teardown()
            return
        }
        synth.fade(to: 0, over: fadeOut)
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(fadeOut + 0.1))
            guard !Task.isCancelled else { return }
            self?.teardown()
        }
    }

    /// Changes the volume (0 to 1) smoothly.
    func setVolume(_ newVolume: Float) {
        volume = Self.clamped(newVolume)
        synth?.fade(to: AmbienceSynth.gain(forVolume: volume), over: 0.15)
    }

    /// Plays again after a pause caused by unplugging headphones. Does nothing if no ambience was chosen.
    func resume() {
        guard synth != nil, currentID != nil else { return }
        wantsPlayback = true
        resumeEngine()
    }

    // MARK: Engine

    private func start(_ recipe: AmbienceRecipe, fadeIn: TimeInterval) {
        teardown()
        guard LeafAudioSession.activate(overridingSilentSwitch: true) else {
            wantsPlayback = false
            currentID = nil
            return
        }
        // In Low Power Mode one channel at half the sample rate is a quarter of the work. The mixer upsamples it.
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let sampleRate = lowPower ? 22_050.0 : 44_100.0
        let channels: AVAudioChannelCount = lowPower ? 1 : 2
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            wantsPlayback = false
            currentID = nil
            return
        }
        startCount += 1
        let seed = SeededGenerator.hash(recipe.rawValue) &+ startCount
        let synth = AmbienceSynth(recipe: recipe, sampleRate: sampleRate, seed: seed, initialGain: 0)
        let node = Self.makeSourceNode(synth: synth, format: format)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        self.synth = synth
        sourceNode = node
        do {
            try engine.start()
        } catch {
            teardown()
            wantsPlayback = false
            currentID = nil
            return
        }
        synth.fade(to: AmbienceSynth.gain(forVolume: volume), over: fadeIn)
        isPlaying = true
    }

    /// Built outside the main actor on purpose: the block runs on the real-time audio thread and must not inherit
    /// main-actor isolation.
    private nonisolated static func makeSourceNode(synth: AmbienceSynth, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let leftData = buffers.first?.mData else { return noErr }
            let left = leftData.assumingMemoryBound(to: Float.self)
            var right: UnsafeMutablePointer<Float>?
            if buffers.count > 1, let rightData = buffers[1].mData {
                right = rightData.assumingMemoryBound(to: Float.self)
            }
            synth.render(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }

    private func resumeEngine() {
        guard wantsPlayback, let synth, sourceNode != nil else { return }
        guard LeafAudioSession.activate(overridingSilentSwitch: true) else { return }
        do {
            if !engine.isRunning { try engine.start() }
            synth.fade(to: AmbienceSynth.gain(forVolume: volume), over: 1)
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    private func pauseEngine() {
        engine.pause()
        isPlaying = false
    }

    private func teardown() {
        if let sourceNode { engine.detach(sourceNode) }
        engine.stop()
        sourceNode = nil
        synth = nil
        isPlaying = false
    }

    private static func clamped(_ volume: Float) -> Float {
        volume.isNaN ? 0 : min(1, max(0, volume))
    }

    // MARK: Interruptions and routes

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in self?.handleInterruption(type: type, options: options) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.handleRouteChange(reason: reason) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeEngine() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.rebuildAfterReset() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            // Without a background audio mode iOS stops the engine when the app is suspended; pick it up again.
            Task { @MainActor in
                guard let self, self.wantsPlayback, !self.engine.isRunning else { return }
                self.resumeEngine()
            }
        })
    }

    private func handleInterruption(type: UInt?, options: UInt?) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            pauseEngine()
        case .ended:
            let flags = AVAudioSession.InterruptionOptions(rawValue: options ?? 0)
            if flags.contains(.shouldResume) { resumeEngine() }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reason: UInt?) {
        guard let reason, let kind = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }
        // Headphones pulled out: stop rather than start playing through the speaker. The reader can resume.
        if kind == .oldDeviceUnavailable, isPlaying {
            wantsPlayback = false
            pauseEngine()
        }
    }

    private func rebuildAfterReset() {
        guard wantsPlayback, let id = currentID, let recipe = AmbienceRecipe(id: id) else { return }
        start(recipe, fadeIn: 1)
    }
}
#endif
