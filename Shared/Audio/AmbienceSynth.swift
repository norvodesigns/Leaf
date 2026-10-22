import Foundation

/// Renders one ambience recipe, forever, into whatever buffers the audio system hands over.
///
/// - Deterministic: the same recipe, sample rate and seed always give the same samples, however the request is
///   split into blocks.
/// - Allocation-free while rendering: the scratch space and every ringing voice are made in `init`.
/// - Safe to steer from another thread: `fade(to:over:)` only leaves a note, which the audio thread picks up at
///   the start of its next block without ever waiting for the lock.
/// - Never louder than `AudioLimiter.ceiling` (about -3 dBFS), whatever the gain.
final class AmbienceSynth: @unchecked Sendable {
    /// The most frames processed at once; longer requests are rendered in pieces.
    static let blockSize = 512
    /// Keeps a mono mix of two uncorrelated channels as loud as either of them.
    private static let monoMix: Float = 0.707_106_8

    let recipe: AmbienceRecipe
    let version: AmbienceRecipe.Version
    let sampleRate: Double
    /// True when it plays a recorded bed (`AmbienceRecording`) rather than synthesising.
    let isRecorded: Bool

    private struct Fade {
        var gain: Float
        var seconds: Double
    }

    private var voice: any AmbienceVoice
    private var ramp: AudioGainRamp
    private let outputScale: Float
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
    private let lock = NSLock()
    private var pendingFade: Fade?

    /// `initialGain` is where the master gain starts (0 for silence that will be faded in, 1 for full level).
    ///
    /// With a `recording` the synth plays that recorded bed instead of making the sound, at the recording's own sample
    /// rate (`sampleRate` is ignored) and level; the fades, the volume curve and the limiter are the same.
    init(
        recipe: AmbienceRecipe,
        sampleRate: Double = 44_100,
        seed: UInt64 = 1,
        initialGain: Float = 1,
        version: AmbienceRecipe.Version = .current,
        recording: AmbienceRecording? = nil
    ) {
        let rate = recording?.sampleRate ?? AudioSampleRate.clamped(sampleRate)
        self.recipe = recipe
        self.version = version
        self.sampleRate = rate
        isRecorded = recording != nil
        if let recording {
            voice = AmbienceRecordedVoice(recording: recording, seed: seed)
            outputScale = AmbienceRecipe.recordedRawToTarget
        } else {
            voice = recipe.makeVoice(sampleRate: rate, seed: seed, version: version)
            outputScale = recipe.rawToTarget(version)
        }
        ramp = AudioGainRamp(value: initialGain)
        scratchLeft = UnsafeMutablePointer<Float>.allocate(capacity: AmbienceSynth.blockSize)
        scratchRight = UnsafeMutablePointer<Float>.allocate(capacity: AmbienceSynth.blockSize)
        scratchLeft.initialize(repeating: 0, count: AmbienceSynth.blockSize)
        scratchRight.initialize(repeating: 0, count: AmbienceSynth.blockSize)
    }

    deinit {
        scratchLeft.deallocate()
        scratchRight.deallocate()
    }

    // MARK: Level

    /// Amplitude for a volume slider position (0 to 1). A gentle curve, so the lower half of the slider is not all
    /// the same quiet; out-of-range and non-numeric values are clamped.
    static func gain(forVolume volume: Float) -> Float {
        guard !volume.isNaN else { return 0 }
        let clamped = min(1, max(0, volume))
        return clamped * clamped.squareRoot()
    }

    /// Glides the master gain to `gain` (0 to 1) over `seconds`. Fade in with a positive target, fade out with 0.
    /// Callable from any thread; it takes effect at the start of the next block.
    func fade(to gain: Float, over seconds: Double) {
        lock.lock()
        pendingFade = Fade(gain: gain, seconds: seconds)
        lock.unlock()
    }

    /// The master gain as of the last block rendered.
    var currentGain: Float { ramp.value }

    /// The gain it is heading to (as of the last block rendered).
    var targetGain: Float { ramp.target }

    /// True once a fade to 0 has finished. The synth then renders zeros and does no work.
    var isSilent: Bool { ramp.isSettled && ramp.target == 0 }

    // MARK: Rendering

    /// Fills `left` and, if given, `right` (separate buffers, as `AVAudioSourceNode` hands over for a
    /// non-interleaved format). Without `right` the two channels are mixed down into `left`.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?, frames: Int) {
        guard frames > 0 else { return }
        applyPendingFade()
        var done = 0
        while done < frames {
            let count = min(AmbienceSynth.blockSize, frames - done)
            renderBlock(frames: count, mono: right == nil)
            (left + done).update(from: scratchLeft, count: count)
            if let right { (right + done).update(from: scratchRight, count: count) }
            done += count
        }
    }

    /// Fills one interleaved buffer of `frames * channels` samples (1 or 2 channels).
    func render(into buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int = 2) {
        guard frames > 0 else { return }
        applyPendingFade()
        let stereo = channels >= 2
        var done = 0
        while done < frames {
            let count = min(AmbienceSynth.blockSize, frames - done)
            renderBlock(frames: count, mono: !stereo)
            if stereo {
                let base = buffer + done * 2
                for frame in 0..<count {
                    base[frame * 2] = scratchLeft[frame]
                    base[frame * 2 + 1] = scratchRight[frame]
                }
            } else {
                (buffer + done).update(from: scratchLeft, count: count)
            }
            done += count
        }
    }

    private func applyPendingFade() {
        // Never wait for the main thread: if it is mid-update, the note is picked up on the next block.
        guard lock.try() else { return }
        defer { lock.unlock() }
        if let fade = pendingFade {
            ramp.ramp(to: fade.gain, seconds: fade.seconds, sampleRate: sampleRate)
            pendingFade = nil
        }
    }

    /// Renders up to `blockSize` frames into the scratch buffers, finished (level, fades and limiter).
    private func renderBlock(frames: Int, mono: Bool) {
        if ramp.isSettled && ramp.target == 0 {
            scratchLeft.update(repeating: 0, count: frames)
            scratchRight.update(repeating: 0, count: frames)
            return
        }
        voice.render(left: scratchLeft, right: scratchRight, frames: frames)
        let scale = outputScale
        if ramp.isSettled {
            let gain = ramp.target * scale
            for frame in 0..<frames {
                scratchLeft[frame] *= gain
                scratchRight[frame] *= gain
            }
        } else {
            for frame in 0..<frames {
                let gain = ramp.next() * scale
                scratchLeft[frame] *= gain
                scratchRight[frame] *= gain
            }
        }
        if mono {
            for frame in 0..<frames {
                scratchLeft[frame] = AudioLimiter.limit((scratchLeft[frame] + scratchRight[frame]) * AmbienceSynth.monoMix)
            }
        } else {
            for frame in 0..<frames {
                scratchLeft[frame] = AudioLimiter.limit(scratchLeft[frame])
                scratchRight[frame] = AudioLimiter.limit(scratchRight[frame])
            }
        }
    }
}
