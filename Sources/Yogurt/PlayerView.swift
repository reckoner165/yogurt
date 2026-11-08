import SwiftUI
import AVKit

/// Dumb rendering surface around AVKit's AVPlayerView. To move to fully custom
/// controls later, replace this file with an AVPlayerLayer-backed view plus
/// SwiftUI transport controls driven by the same PlayerController.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = SeeThroughPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

/// AVPlayerView whose audio-only placeholder (grey fill + QuickTime "Q") lets
/// what's behind it show through: the grey becomes a translucent black scrim.
/// AVKit has no API for this, so the private views are matched by class name;
/// if a future macOS renames them this does nothing and the grey comes back.
final class SeeThroughPlayerView: AVPlayerView {
    static let logoOpacity: CGFloat = 1
    /// Black between the backdrop image and the Q.
    static let scrimOpacity: CGFloat = 0.8
    private var itemObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?

    override var player: AVPlayer? {
        didSet { observeItems() }
    }

    override func layout() {
        super.layout()
        Self.clearAudioOnlyIndicator(in: self)
    }

    /// AVKit adds the placeholder once a new item is ready to play, without
    /// laying this view out again, so re-apply then.
    private func observeItems() {
        itemObservation = player?.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        Self.clearAudioOnlyIndicator(in: self)
                    }
                }
            }
        }
    }

    private static func clearAudioOnlyIndicator(in view: NSView) {
        for sub in view.subviews {
            if NSStringFromClass(type(of: sub)) == "AVAudioOnlyIndicatorView" {
                sub.layer?.backgroundColor = NSColor.black.withAlphaComponent(scrimOpacity).cgColor
                for logo in sub.subviews { logo.alphaValue = logoOpacity }
                return
            }
            clearAudioOnlyIndicator(in: sub)
        }
    }
}
