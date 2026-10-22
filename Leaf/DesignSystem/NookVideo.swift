import AVFoundation
import SwiftUI
import UIKit

/// A filmed loop for a nook scene, when the app has one: `nook-rain`, `nook-hearth`, `nook-landscape` (.mp4 or .mov,
/// anywhere in the app bundle, e.g. `Leaf/Resources/Scenes`). Muted, filling the screen, looping without a seam
/// (`AVPlayerLooper`). Without a file the scene falls back to its shader (`NookShaderView`).
///
/// It plays only while the scene may move; a paused session, Reduce Motion, Low Power Mode or the app going inactive
/// pauses it on its current frame.
enum NookVideo {
    static func url(for scene: NookScene) -> URL? {
        let name = "nook-\(scene.rawValue)"
        for ext in ["mp4", "mov", "m4v"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Scenes") { return url }
        }
        return nil
    }
}

struct NookVideoView: UIViewRepresentable {
    let url: URL
    var isPlaying: Bool

    func makeUIView(context: Context) -> NookVideoPlayerView {
        let view = NookVideoPlayerView(url: url)
        view.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ view: NookVideoPlayerView, context: Context) {
        view.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: NookVideoPlayerView, coordinator: ()) {
        view.setPlaying(false)
    }
}

final class NookVideoPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .black
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // The scene is decoration: it never takes the audio session from the ambience or the reader's music.
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        if let layer = layer as? AVPlayerLayer {
            layer.player = player
            layer.videoGravity = .resizeAspectFill
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setPlaying(_ playing: Bool) {
        if playing {
            if player.timeControlStatus != .playing { player.play() }
        } else {
            player.pause()
        }
    }
}
