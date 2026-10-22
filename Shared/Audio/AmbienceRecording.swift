import Foundation

/// A recorded bed for an ambience: a stretch of a real CC0 recording (see docs/AUDIO_SOURCES.md), cleaned and levelled
/// to its recipe's loudness ahead of time, held in memory as a seamless stereo loop.
///
/// The app decodes the bundled file (`AmbienceRecipe.recordingName`) and hands the samples over; this type is
/// Foundation-only so the loop itself can be tested anywhere. Each file runs `crossfadeSeconds` longer than its loop:
/// that tail is faded into the start here (`AudioLoop.seamless`), so the join never clicks, whatever the encoder
/// padded at either end.
final class AmbienceRecording: @unchecked Sendable {
    /// The tail each file carries for its join.
    static let crossfadeSeconds = 2.0
    /// Trimmed from both ends before the join: room for an encoder's priming and padding.
    static let edgeSeconds = 0.05

    let sampleRate: Double
    /// Frames in one pass of the loop.
    let frameCount: Int
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>

    /// `left` and `right` are the decoded file (pass the same samples twice for a mono file). Nil when there is too
    /// little to loop.
    init?(left: [Float], right: [Float], sampleRate: Double) {
        let rate = AudioSampleRate.clamped(sampleRate)
        let edge = Int(Self.edgeSeconds * rate)
        let fade = Int(Self.crossfadeSeconds * rate)
        let usable = min(left.count, right.count) - 2 * edge
        guard usable > fade * 4 else { return nil }
        let loopLeft = AudioLoop.seamless(Array(left[edge..<(edge + usable)]), crossfade: fade)
        let loopRight = AudioLoop.seamless(Array(right[edge..<(edge + usable)]), crossfade: fade)
        self.sampleRate = rate
        frameCount = loopLeft.count
        self.left = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        self.right = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        loopLeft.withUnsafeBufferPointer { self.left.initialize(from: $0.baseAddress!, count: frameCount) }
        loopRight.withUnsafeBufferPointer { self.right.initialize(from: $0.baseAddress!, count: frameCount) }
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    /// How long one pass lasts.
    var seconds: Double { Double(frameCount) / sampleRate }
}

/// Plays a recording round and round, allocation-free. Each start opens somewhere else in the loop (by seed), so two
/// sessions don't begin on the same crackle.
struct AmbienceRecordedVoice: AmbienceVoice {
    private let recording: AmbienceRecording
    private var position: Int

    init(recording: AmbienceRecording, seed: UInt64) {
        self.recording = recording
        position = Int(seed % UInt64(recording.frameCount))
    }

    mutating func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        var done = 0
        while done < frames {
            let count = min(frames - done, recording.frameCount - position)
            (left + done).update(from: recording.left + position, count: count)
            (right + done).update(from: recording.right + position, count: count)
            done += count
            position += count
            if position >= recording.frameCount { position = 0 }
        }
    }
}

extension AmbienceRecipe {
    /// The bundled recording's file name, without its extension (`ambience-rain.m4a`, ...).
    var recordingName: String { "ambience-\(rawValue)" }

    /// The recordings are levelled offline, so they play at their own level: no gain on top.
    static let recordedRawToTarget: Float = 1
}
