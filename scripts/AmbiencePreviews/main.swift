import Foundation

// Renders the ambience previews with the app's own synthesis (everything in Shared/): every recipe as it is now and,
// beside it, as the first TestFlight had it, plus the cues, as 16-bit WAV files, and a table of what each one
// measures. scripts/render_ambience_previews.sh compiles this with Shared/ and turns the WAVs into .m4a.

let outDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "previews")
try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
let rate = 44_100.0

func pcm16(_ value: Float) -> Int16 {
    Int16(max(-32_767, min(32_767, (value * 32_767).rounded())))
}

func writeWAV(left: [Float], right: [Float]?, name: String) {
    let channels = right == nil ? 1 : 2
    let frames = left.count
    var data = Data()
    func append32(_ value: UInt32) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 4)) }
    func append16(_ value: UInt16) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 2)) }
    let bytes = UInt32(frames * channels * 2)
    data.append(contentsOf: Array("RIFF".utf8))
    append32(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    append32(16)
    append16(1)
    append16(UInt16(channels))
    append32(UInt32(rate))
    append32(UInt32(rate) * UInt32(channels) * 2)
    append16(UInt16(channels * 2))
    append16(16)
    data.append(contentsOf: Array("data".utf8))
    append32(bytes)
    var samples = [Int16]()
    samples.reserveCapacity(frames * channels)
    for index in 0..<frames {
        samples.append(pcm16(left[index]))
        if let right { samples.append(pcm16(right[index])) }
    }
    samples.withUnsafeBufferPointer { buffer in
        data.append(Data(buffer: buffer))
    }
    try? data.write(to: outDirectory.appendingPathComponent(name + ".wav"))
}

func render(_ recipe: AmbienceRecipe, version: AmbienceRecipe.Version, seconds: Double) -> (left: [Float], right: [Float]) {
    // Faded in over a second, as the player does, so the preview doesn't start with a jolt.
    let synth = AmbienceSynth(recipe: recipe, sampleRate: rate, seed: 7, initialGain: 0, version: version)
    synth.fade(to: 1, over: 1)
    let frames = Int(seconds * rate)
    var left = [Float](repeating: 0, count: frames)
    var right = [Float](repeating: 0, count: frames)
    left.withUnsafeMutableBufferPointer { l in
        right.withUnsafeMutableBufferPointer { r in
            guard let leftBase = l.baseAddress, let rightBase = r.baseAddress else { return }
            var done = 0
            while done < frames {
                let count = min(512, frames - done)
                synth.render(left: leftBase + done, right: rightBase + done, frames: count)
                done += count
            }
        }
    }
    return (left, right)
}

func format(_ value: Double, _ digits: Int = 1) -> String { String(format: "%.\(digits)f", value) }

var table = """
| Sound | Recipe | LUFS | Hiss between events (dB) | Events over the room, phone band (dB) | Ringing (0 noise, 1 pitched) | Transients a second | Narrow peak (dB) |
|---|---|---|---|---|---|---|---|

"""
for recipe in AmbienceRecipe.allCases {
    let versions: [AmbienceRecipe.Version] = recipe == .rain ? [.current] : [.current, .original]
    for version in versions {
        // The kettle gets longer, so its rise to the simmer can be heard.
        let seconds = recipe == .kettle ? 45.0 : 30.0
        let sound = render(recipe, version: version, seconds: seconds)
        let name = recipe == .rain ? recipe.rawValue : "\(recipe.rawValue)-\(version == .current ? "new" : "old")"
        writeWAV(left: sound.left, right: sound.right, name: name)
        let settle = recipe == .kettle ? 32.0 : 2.0
        let start = Int(settle * rate)
        let left = Array(sound.left[start...])
        let right = Array(sound.right[start...])
        let mono = AudioMeasure.mono(left, right)
        let onsets = AudioMeasure.onsets(mono, sampleRate: rate)
        let spacing = AudioMeasure.spacing(onsets, seconds: seconds - settle, sampleRate: rate)
        let row = [
            recipe.rawValue,
            version.rawValue,
            format(AudioMeasure.loudness(left: left, right: right, sampleRate: rate)),
            format(AudioMeasure.quietHiss(mono, sampleRate: rate)),
            format(AudioMeasure.phoneBandContrast(mono, sampleRate: rate)),
            onsets.count >= 3 ? format(AudioMeasure.ringing(mono, onsets: onsets, sampleRate: rate), 2) : "–",
            format(spacing.rate),
            format(AudioMeasure.tonalPeak(mono, sampleRate: rate)),
        ]
        table += "| " + row.joined(separator: " | ") + " |\n"
        print(name, row.joined(separator: " "))
    }
}
for cue in CozyCue.allCases {
    writeWAV(left: CozyCueSynth.render(cue, sampleRate: rate, seed: 1), right: nil, name: "cue-\(cue.rawValue)")
}
try? table.write(to: outDirectory.appendingPathComponent("MEASURES.md"), atomically: true, encoding: .utf8)
