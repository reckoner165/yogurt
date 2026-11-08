import SwiftUI
import AppKit

/// Two-tone surface palette: grey behind media, the text-editor colour behind notes.
/// These stay solid; the window itself sits on `WindowBackdrop`.
enum Theme {
    /// AVPlayerView's background behind the audio-only QuickTime logo (sampled: #424245).
    static let mediaSurface = Color(red: 0x42 / 255, green: 0x42 / 255, blue: 0x45 / 255)
    /// Matches the notes NSTextView's own background (#1e1e1e in dark mode).
    static let notesSurface = Color(nsColor: .textBackgroundColor)

    /// Artwork behind the player's audio-only "Q". Looked up like Fonts:
    /// the .app's Resources, else <repo>/Resources for a bare binary.
    static let playerBackdrop: NSImage? = {
        var candidates: [URL] = []
        if let bundled = Bundle.main.resourceURL {
            candidates.append(bundled.appendingPathComponent("Images/player-backdrop.png"))
        }
        if let exe = Bundle.main.executableURL {
            candidates.append(
                exe.deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources/Images/player-backdrop.png")
            )
        }
        for url in candidates {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }()
}

/// Translucent window background: blurs whatever is behind the window
/// (desktop, other apps) instead of the flat window grey.
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    /// Below 1 lets a little of the unblurred background through.
    var opacity: CGFloat = 0.95
    /// Black laid over the blur; higher is closer to black.
    var darkness: CGFloat = 0.25

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        // Keep the blur when the window is inactive instead of falling back to grey.
        view.state = .active
        view.material = material
        view.alphaValue = opacity

        let tint = NSView(frame: view.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(darkness).cgColor
        view.addSubview(tint)
        // The window must be non-opaque, or its grey shows through instead of the desktop.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            // Let the backdrop run up behind the title bar / toolbar too.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
        }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.alphaValue = opacity
        view.subviews.first?.layer?.backgroundColor = NSColor.black.withAlphaComponent(darkness).cgColor
    }
}
