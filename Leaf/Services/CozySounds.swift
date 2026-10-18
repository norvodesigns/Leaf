#if canImport(AVFoundation)
import AVFoundation

/// The little sounds of the tea ritual and the page: a kettle click, a pour, a two-note chime when the tea is ready,
/// a page turn. They are synthesised once by `CozyCueSynth` into small buffers (no audio files) and played through
/// their own light engine, which switches itself off a few seconds after the last sound.
///
/// Sound has its own preference, apart from haptics: set `isEnabled` from it. Cues follow the silent switch unless
/// ambience is already playing (see `LeafAudioSession`), and mix with whatever the reader is listening to.
@MainActor
final class CozySounds {
    static let shared = CozySounds()

    /// The reader's sound preference. Nothing plays while this is false.
    /// Off until the reader turns sounds on: nothing in Leaf makes a noise by surprise.
    var isEnabled = false
    /// 0 to 1. Cues are small already, so this is a trim, not the main control.
    var volume: Float = 0.7

    private static let sampleRate = 44_100.0
    private static let voiceCount = 3

    private let engine = AVAudioEngine()
    private var format: AVAudioFormat?
    private var nodes: [AVAudioPlayerNode] = []
    private var busy: [Bool] = []
    private var buffers: [CozyCue: AVAudioPCMBuffer] = [:]
    private var idleTask: Task<Void, Never>?
    /// Bumped by `cancelPending()` so cues that were scheduled for later do not play.
    private var generation = 0

    private init() {}

    // MARK: Playing

    /// Renders every cue ahead of time, off the main thread, so the first sound has no hitch. Safe to call often.
    func prepare() {
        guard isEnabled, prepareGraph() else { return }
        let rate = Self.sampleRate
        for cue in CozyCue.allCases where buffers[cue] == nil {
            Task.detached(priority: .utility) {
                let samples = CozyCueSynth.render(cue, sampleRate: rate)
                await CozySounds.shared.store(samples, for: cue)
            }
        }
    }

    /// Plays a cue, now or after `delay` seconds. Does nothing while sound is turned off.
    func play(_ cue: CozyCue, after delay: TimeInterval = 0) {
        guard isEnabled else { return }
        guard delay > 0 else {
            start(cue)
            return
        }
        let token = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == token else { return }
            self.start(cue)
        }
    }

    /// Plays a group of cues with their delays, such as `CozyCueSequence.brewStart`.
    func play(_ sequence: [CozyCueSequence.Step]) {
        for step in sequence { play(step.cue, after: step.delay) }
    }

    /// Drops any cue that was scheduled for later and has not played yet.
    func cancelPending() {
        generation += 1
    }

    // MARK: For the tea timer

    /// The kettle goes on and the water is poured: call when a steep begins.
    func teaBrewStarted() { play(CozyCueSequence.brewStart) }

    /// The two-note chime: call when the steep timer finishes.
    func teaReady() { play(CozyCueSequence.ready) }

    /// A page turning: call when the reader turns to a new page.
    func pageTurned() { play(.pageTurn) }

    // MARK: Engine

    private func store(_ samples: [Float], for cue: CozyCue) {
        guard buffers[cue] == nil, let format, let buffer = Self.makeBuffer(samples, format: format) else { return }
        buffers[cue] = buffer
    }

    private static func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// Attaches the player nodes the first time they are needed.
    private func prepareGraph() -> Bool {
        if !nodes.isEmpty { return true }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return false }
        self.format = format
        for _ in 0..<Self.voiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            nodes.append(node)
        }
        busy = Array(repeating: false, count: Self.voiceCount)
        return true
    }

    private func buffer(for cue: CozyCue) -> AVAudioPCMBuffer? {
        if let ready = buffers[cue] { return ready }
        // Not prepared yet: a cue is a few tens of milliseconds of work, so make it now.
        guard let format, let made = Self.makeBuffer(CozyCueSynth.render(cue, sampleRate: Self.sampleRate), format: format) else { return nil }
        buffers[cue] = made
        return made
    }

    private func start(_ cue: CozyCue) {
        guard isEnabled, prepareGraph(), let buffer = buffer(for: cue) else { return }
        idleTask?.cancel()
        idleTask = nil
        // Ambience already overrides the silent switch; a lone cue should not.
        guard LeafAudioSession.activate(overridingSilentSwitch: AmbiencePlayer.shared.isPlaying) else { return }
        if !engine.isRunning {
            // A stopped engine drops whatever was queued, so every voice is free again.
            busy = Array(repeating: false, count: Self.voiceCount)
            do { try engine.start() } catch { return }
        }
        guard let index = busy.firstIndex(of: false) else { return }
        busy[index] = true
        let node = nodes[index]
        node.volume = volume.isNaN ? 0 : min(1, max(0, volume))
        node.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.finished(index) }
        }
        node.play()
    }

    private func finished(_ index: Int) {
        guard busy.indices.contains(index) else { return }
        busy[index] = false
        guard !busy.contains(true) else { return }
        // Let the engine go a few seconds after the last sound so it costs nothing while the reader reads.
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, !self.busy.contains(true) else { return }
            self.engine.stop()
        }
    }
}
#endif
