import SwiftUI
import AppKit

/// Two-tone surface palette: grey behind media, the text-editor colour behind notes.
/// Solid colours on purpose — system materials pick up a wallpaper tint in dark mode.
enum Theme {
    /// AVPlayerView's background behind the audio-only QuickTime logo (sampled: #424245).
    static let mediaSurface = Color(red: 0x42 / 255, green: 0x42 / 255, blue: 0x45 / 255)
    /// Matches the notes NSTextView's own background (#1e1e1e in dark mode).
    static let notesSurface = Color(nsColor: .textBackgroundColor)
}
