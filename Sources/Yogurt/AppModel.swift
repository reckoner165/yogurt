import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let player = PlayerController()
    let notes = NotesStore()

    @Published private(set) var mediaURL: URL?

    func open(_ url: URL) {
        notes.flushNow()
        mediaURL = url
        player.load(url: url)
        notes.open(mediaURL: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func insertTimestamp() {
        guard mediaURL != nil else { return }
        NotificationCenter.default.post(
            name: .yogurtInsertText,
            object: nil,
            userInfo: ["text": player.timestampMarker + " "]
        )
    }
}
