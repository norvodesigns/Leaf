import SwiftUI

/// The Sound lab: every ambience as it is now and as the first TestFlight had it, side by side at one volume, and
/// every cue, for judging the sounds by ear on the phone itself. Nothing plays until a button is tapped, and leaving
/// stops whatever the lab started. Always in Settings in debug builds; in others, seven taps on the version number
/// reveal it.
struct SoundLabView: View {
    @State private var volume: Double = 0.6
    @State private var started = false

    private var player: AmbiencePlayer { AmbiencePlayer.shared }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Space.m) {
                    Image(systemName: "speaker.wave.1").foregroundStyle(Color.inkTertiary)
                    Slider(value: $volume, in: 0...1)
                        .accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3").foregroundStyle(Color.inkTertiary)
                }
                .onChange(of: volume) { _, newValue in
                    player.setVolume(Float(newValue))
                }
            } header: {
                Text("Volume").leafStyle(.eyebrow)
            } footer: {
                Text("Every sound is made to the same loudness, so moving between them at one volume should feel even. The library is quieter on purpose.")
                    .leafStyle(.caption)
            }

            Section {
                ForEach(AmbienceCatalog.sounds) { sound in
                    if let recipe = AmbienceRecipe(id: sound.id) {
                        row(sound, recipe: recipe)
                    }
                }
            } header: {
                Text("Ambience").leafStyle(.eyebrow)
            } footer: {
                Text("New is this version’s; Old is the first TestFlight’s, to compare. Rain is the same in both.")
                    .leafStyle(.caption)
            }

            Section {
                ForEach(CozyCue.allCases, id: \.self) { cue in
                    Button {
                        CozySounds.shared.audition(cue)
                    } label: {
                        HStack {
                            Text(Self.title(cue)).leafStyle(.uiBody)
                            Spacer()
                            Image(systemName: "play.circle")
                                .foregroundStyle(Color.accent)
                        }
                        .frame(minHeight: Space.hitTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(Self.title(cue))")
                }
            } header: {
                Text("Cues").leafStyle(.eyebrow)
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
        HStack(spacing: Space.m) {
            Image(systemName: sound.symbol)
                .frame(width: 24)
                .foregroundStyle(Color.inkSecondary)
                .accessibilityHidden(true)
            Text(sound.name)
                .leafStyle(.uiBody)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Space.s)
            if recipe != .rain {
                toggle(sound, version: .original, title: "Old")
            }
            toggle(sound, version: .current, title: "New")
        }
        .frame(minHeight: Space.hitTarget)
    }

    private func isPlaying(_ sound: Ambience, _ version: AmbienceRecipe.Version) -> Bool {
        player.isPlaying && player.currentID == sound.id && player.version == version
    }

    private func toggle(_ sound: Ambience, version: AmbienceRecipe.Version, title: String) -> some View {
        let playing = isPlaying(sound, version)
        return Button {
            Haptics.shared.selection()
            if playing {
                player.stop(fadeOut: 0.4)
            } else {
                started = true
                player.play(sound.id, volume: Float(volume), fadeIn: 0.6, version: version)
            }
        } label: {
            Label(title, systemImage: playing ? "stop.fill" : "play.fill")
                .labelStyle(.titleAndIcon)
                .font(LeafType.ui)
                .padding(.horizontal, Space.m)
                .frame(minHeight: 36)
                .background(Capsule().fill(playing ? Color.accent.opacity(0.18) : Color.paperSunken))
                .foregroundStyle(playing ? Color.accent : Color.ink)
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
