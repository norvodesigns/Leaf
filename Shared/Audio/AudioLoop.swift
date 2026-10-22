import Foundation

/// Turning a recording into a loop that never clicks at its join, for the recorded beds (`AmbienceRecording`, see
/// docs/AUDIO_SOURCES.md). The procedural sounds never repeat and don't need it.
enum AudioLoop {
    /// The recording shortened by `crossfade` frames, with its last `crossfade` frames faded (equal power) into its
    /// first ones, so the end runs straight on into the start.
    static func seamless(_ samples: [Float], crossfade: Int) -> [Float] {
        let length = samples.count
        let fade = min(max(0, crossfade), length / 2)
        guard fade > 0 else { return samples }
        var loop = Array(samples[0..<(length - fade)])
        for index in 0..<fade {
            let angle = Float(index) / Float(fade) * Float.pi / 2
            loop[index] = samples[index] * sin(angle) + samples[length - fade + index] * cos(angle)
        }
        return loop
    }

    /// The step from the loop's last sample to its first, against the 99th percentile of every other step: about 1
    /// or less for a clean join, many times that for a click.
    static func seamJump(_ loop: [Float]) -> Double {
        guard loop.count > 2, let first = loop.first, let last = loop.last else { return 0 }
        var steps: [Double] = []
        steps.reserveCapacity(loop.count - 1)
        for index in 1..<loop.count { steps.append(Double(abs(loop[index] - loop[index - 1]))) }
        let typical = AudioMeasure.percentile(steps, 0.99)
        return Double(abs(first - last)) / max(typical, 1e-12)
    }
}
