import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let player = PlayerController()
    let notes = NotesStore()
    let status = StatusCenter()

    @Published private(set) var mediaURL: URL?
    @Published private(set) var showMeter = false

    private init() {
        status.setIdle("No file open — ⌘O to open")
        notes.onStatus = { [weak self] message in
            self?.status.transient(message)
        }
    }

    func open(_ url: URL) {
        notes.flushNow()
        mediaURL = url
        player.load(url: url)
        let notesURL = NotesStore.notesURL(for: url)
        let hadNotes = FileManager.default.fileExists(atPath: notesURL.path)
        notes.open(mediaURL: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        status.setIdle("notes/\(notesURL.lastPathComponent)")
        status.transient(
            hadNotes
                ? "Opened \(url.lastPathComponent) — existing notes loaded"
                : "Opened \(url.lastPathComponent) — new notes file"
        )
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
        let marker = player.timestampMarker
        NotificationCenter.default.post(
            name: .yogurtInsertText,
            object: nil,
            userInfo: ["text": marker + " "]
        )
        status.transient("Inserted \(marker)")
    }

    func toggleMeter() {
        showMeter.toggle()
        if showMeter {
            player.meter.startMetering()
        } else {
            player.meter.stopMetering()
        }
        status.transient(showMeter ? "Audio meter on" : "Audio meter off")
    }

    func seek(to seconds: Double) {
        player.seek(to: seconds)
        status.transient("Jumped to \(PlayerController.format(seconds))")
    }
}
