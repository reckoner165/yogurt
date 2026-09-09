import AVFoundation
import Combine

/// Owns the AVPlayer engine. All playback state and commands live here so the
/// rendering surface (PlayerView) can be swapped for custom controls later.
@MainActor
final class PlayerController: ObservableObject {
    let player = AVPlayer()

    @Published private(set) var currentTime: Double = 0

    private var timeObserver: Any?

    init() {
        let interval = CMTime(value: 1, timescale: 4)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds.isFinite ? time.seconds : 0
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    /// Current playback position formatted for insertion into notes, e.g. "[3:07]" or "[1:02:45]".
    var timestampMarker: String {
        "[\(Self.format(currentTime))]"
    }

    static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
