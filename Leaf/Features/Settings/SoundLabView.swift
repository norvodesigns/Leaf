import SwiftUI

/// The Sound lab: every ambience as it is now and as the first TestFlight had it, side by side at one volume, and
/// every cue, for judging the sounds by ear on the phone itself. Nothing plays until a button is tapped, and leaving
/// stops whatever the lab started. Always in Settings in debug builds; in TestFlight builds, seven taps on the version
/// number reveal it. App Store builds never show it.
struct SoundLabView: View {
    @State private var volume: Double = 0.6
    @State private var started = false

    private var player: AmbiencePlayer { AmbiencePlayer.shared }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Canopy.Space.m) {
                    Image(systemName: "speaker.wave.1").foregroundStyle(Canopy.textTertiary)
                    Slider(value: $volume, in: 0...1)
                        .accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3").foregroundStyle(Canopy.textTertiary)
                }
                .onChange(of: volume) { _, newValue in
                    player.setVolume(Float(newValue))
                }
            } header: {
                Text("Volume").settingsHeader()
            } footer: {
                Text("Every sound is made to the same loudness, so moving between them at one volume should feel even. The library is quieter on purpose.")
                    .canopyText(.caption)
            }

            Section {
                ForEach(AmbienceCatalog.sounds) { sound in
                    if let recipe = AmbienceRecipe(id: sound.id) {
                        row(sound, recipe: recipe)
                    }
                }
            } header: {
                Text("Ambience").settingsHeader()
            } footer: {
                Text("New is this version’s; Old is the first TestFlight’s, to compare. Rain is the same in both.")
                    .canopyText(.caption)
            }

            Section {
                ForEach(CozyCue.allCases, id: \.self) { cue in
                    Button {
                        CozySounds.shared.audition(cue)
                    } label: {
                        HStack {
                            Text(Self.title(cue)).canopyText(.body)
                            Spacer()
                            Image(systemName: "play.circle")
                                .foregroundStyle(CanopyAccent.forest.color)
                        }
                        .frame(minHeight: Canopy.Space.hitTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(Self.title(cue))")
                }
            } header: {
                Text("Cues").settingsHeader()
            }
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        .navigationTitle("Sound lab")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if started { player.stop(fadeOut: 0.6) }
        }
    }

    private func row(_ sound: Ambience, recipe: AmbienceRecipe) -> some View {
        HStack(spacing: Canopy.Space.m) {
            Image(systemName: sound.symbol)
                .frame(width: 24)
                .foregroundStyle(Canopy.textSecondary)
                .accessibilityHidden(true)
            Text(sound.name)
                .canopyText(.body)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Canopy.Space.s)
            if recipe != .rain {
                toggle(sound, version: .original, title: "Old")
            }
            toggle(sound, version: .current, title: "New")
        }
        .frame(minHeight: Canopy.Space.hitTarget)
    }

    private func isPlaying(_ sound: Ambience, _ version: AmbienceRecipe.Version) -> Bool {
        player.isPlaying && player.currentID == sound.id && player.version == version
    }

    private func toggle(_ sound: Ambience, version: AmbienceRecipe.Version, title: String) -> some View {
        let playing = isPlaying(sound, version)
        return Button {
            CanopyFeel.play(.select)
            if playing {
                player.stop(fadeOut: 0.4)
            } else {
                started = true
                player.play(sound.id, volume: Float(volume), fadeIn: 0.6, version: version)
            }
        } label: {
            Label(title, systemImage: playing ? "stop.fill" : "play.fill")
                .labelStyle(.titleAndIcon)
                .font(CanopyType.callout.font)
                .padding(.horizontal, Canopy.Space.m)
                .frame(minHeight: 36)
                .background(Capsule().fill(playing ? CanopyAccent.forest.color.opacity(0.18) : Canopy.separator))
                .foregroundStyle(playing ? CanopyAccent.forest.color : Canopy.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(sound.name), \(version == .current ? "new" : "old") version")
        .accessibilityValue(playing ? "Playing" : "")
    }

    static func title(_ cue: CozyCue) -> String {
        switch cue {
        case .kettleClick: return "Kettle switch"
        case .pour: return "Pour"
        case .steepReady: return "Tea is ready"
        case .pageTurn: return "Page turn"
        }
    }
}
