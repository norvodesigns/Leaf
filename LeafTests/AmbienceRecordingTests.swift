import Foundation
import Testing
#if canImport(LeafCore)
@testable import LeafCore
#else
@testable import Leaf
#endif

/// The recorded beds: a decoded file becomes a seamless loop, and the synth plays it at its own rate and level.
struct AmbienceRecordingTests {
    private static let rate = 8_000.0

    /// Ten seconds of quiet pink noise riding a slow ramp, different on each side: as a plain loop it would click.
    private static func file(seconds: Double = 10) -> (left: [Float], right: [Float]) {
        var leftNoise = AudioNoiseSource(color: .pink, seed: 11, sampleRate: rate)
        var rightNoise = AudioNoiseSource(color: .pink, seed: 12, sampleRate: rate)
        let count = Int(seconds * rate)
        var left: [Float] = []
        var right: [Float] = []
        for index in 0..<count {
            // Kept well under the limiter's knee, so a sample played back is exactly the sample stored.
            let ramp = Float(index) / Float(count) * 0.2
            left.append(leftNoise.next() * 0.03 + ramp)
            right.append(rightNoise.next() * 0.03 - ramp)
        }
        return (left, right)
    }

    /// Renders `frames` frames in uneven blocks, the way the audio system asks for them.
    private static func render(_ synth: AmbienceSynth, frames: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        let blocks = [256, 1_000, 37, 4_096]
        var done = 0
        var block = 0
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                while done < frames {
                    let count = min(blocks[block % blocks.count], frames - done)
                    synth.render(left: leftBuffer.baseAddress! + done, right: rightBuffer.baseAddress! + done, frames: count)
                    done += count
                    block += 1
                }
            }
        }
        return (left, right)
    }

    @Test func aDecodedFileBecomesALoopThatJoinsWithoutAClick() throws {
        let file = Self.file()
        let plain: Double = AudioLoop.seamJump(file.left)
        let recording = try #require(AmbienceRecording(left: file.left, right: file.right, sampleRate: Self.rate))
        let edge = Int(AmbienceRecording.edgeSeconds * Self.rate)
        let fade = Int(AmbienceRecording.crossfadeSeconds * Self.rate)
        #expect(recording.frameCount == file.left.count - 2 * edge - fade)
        #expect(abs(recording.seconds - (10 - 2 * AmbienceRecording.edgeSeconds - AmbienceRecording.crossfadeSeconds)) < 0.001)
        let left = Array(UnsafeBufferPointer(start: recording.left, count: recording.frameCount))
        let right = Array(UnsafeBufferPointer(start: recording.right, count: recording.frameCount))
        let joinedLeft: Double = AudioLoop.seamJump(left)
        let joinedRight: Double = AudioLoop.seamJump(right)
        #expect(plain > 3, "the plain file clicks: \(plain)")
        #expect(joinedLeft < 1.5 && joinedRight < 1.5, "joins: \(joinedLeft), \(joinedRight)")
    }

    @Test func tooLittleToLoopIsNil() {
        let short = [Float](repeating: 0.1, count: Int(Self.rate * 3))
        #expect(AmbienceRecording(left: short, right: short, sampleRate: Self.rate) == nil)
        #expect(AmbienceRecording(left: [], right: [], sampleRate: Self.rate) == nil)
    }

    @Test func theSynthPlaysTheRecordingAtItsOwnRateAndLevelRoundAndRound() throws {
        let file = Self.file()
        let recording = try #require(AmbienceRecording(left: file.left, right: file.right, sampleRate: Self.rate))
        // Seed 0 starts at the top of the loop; the requested 44.1 kHz gives way to the recording's own rate.
        let synth = AmbienceSynth(recipe: .fireplace, sampleRate: 44_100, seed: 0, initialGain: 1, recording: recording)
        #expect(synth.isRecorded)
        #expect(synth.sampleRate == Self.rate)
        let frames = recording.frameCount * 2 + 123
        let out = Self.render(synth, frames: frames)
        var mismatches = 0
        for index in 0..<frames {
            let source = index % recording.frameCount
            if out.left[index] != recording.left[source] || out.right[index] != recording.right[source] { mismatches += 1 }
        }
        #expect(mismatches == 0, "every sample is the recording's, at gain 1, wrapping at the loop's length")
    }

    @Test func eachStartOpensSomewhereElseInTheLoop() throws {
        let file = Self.file()
        let recording = try #require(AmbienceRecording(left: file.left, right: file.right, sampleRate: Self.rate))
        let seed: UInt64 = 1_234_567
        let synth = AmbienceSynth(recipe: .rain, seed: seed, initialGain: 1, recording: recording)
        let out = Self.render(synth, frames: 64)
        let start = Int(seed % UInt64(recording.frameCount))
        #expect(start != 0)
        #expect(out.left[0] == recording.left[start])
        #expect(out.left[63] == recording.left[(start + 63) % recording.frameCount])
    }

    @Test func fadesStillApplyToARecording() throws {
        let file = Self.file()
        let recording = try #require(AmbienceRecording(left: file.left, right: file.right, sampleRate: Self.rate))
        let synth = AmbienceSynth(recipe: .cafe, seed: 0, initialGain: 0, recording: recording)
        let silent = Self.render(synth, frames: 512)
        #expect(silent.left.allSatisfy { $0 == 0 })
        synth.fade(to: 1, over: 0.25)
        _ = Self.render(synth, frames: Int(Self.rate * 0.3))
        #expect(synth.currentGain == 1)
    }

    @Test func everyRecipeNamesItsBundledFile() {
        #expect(AmbienceRecipe.allCases.map(\.recordingName) == [
            "ambience-rain", "ambience-fireplace", "ambience-kettle", "ambience-cafe", "ambience-library",
        ])
        #expect(AmbienceRecipe.recordedRawToTarget == 1)
    }
}
