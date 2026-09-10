import Foundation

/// Loads and autosaves the markdown notes file that shadows a media file:
/// <media dir>/notes/<media filename>.md. The media file itself is never touched.
@MainActor
final class NotesStore: ObservableObject {
    @Published var text: String = ""

    /// Status messages for the UI (autosave confirmations, errors).
    var onStatus: ((String) -> Void)?

    private(set) var notesURL: URL?

    private var saveWorkItem: DispatchWorkItem?
    private var lastSavedText: String?
    /// Template shown for a brand-new notes file; skipped on save so that
    /// opening a file and typing nothing doesn't litter notes/ directories.
    private var untouchedTemplate: String?

    static func notesURL(for mediaURL: URL) -> URL {
        mediaURL
            .deletingLastPathComponent()
            .appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent(mediaURL.lastPathComponent + ".md")
    }

    func open(mediaURL: URL) {
        flushNow()
        let url = Self.notesURL(for: mediaURL)
        notesURL = url
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            text = existing
            lastSavedText = existing
            untouchedTemplate = nil
        } else {
            let template = "# \(mediaURL.lastPathComponent)\n\n"
            text = template
            lastSavedText = nil
            untouchedTemplate = template
        }
    }

    func noteChanged() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func flushNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard let url = notesURL, text != lastSavedText else { return }
        if lastSavedText == nil, text == untouchedTemplate { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: url, options: .atomic)
            lastSavedText = text
            let time = Date().formatted(date: .omitted, time: .standard)
            onStatus?("Autosaved \(url.lastPathComponent) · \(time)")
        } catch {
            NSLog("Yogurt: failed to save notes to \(url.path): \(error)")
            onStatus?("⚠︎ Could not save notes: \(error.localizedDescription)")
        }
    }
}
