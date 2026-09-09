import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.mediaURL != nil {
                HSplitView {
                    PlayerView(player: model.player.player)
                        .frame(minWidth: 320, minHeight: 240)
                    NotesPane(notes: model.notes) { seconds in
                        model.player.seek(to: seconds)
                    }
                    .frame(minWidth: 260)
                }
            } else {
                EmptyStateView()
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .navigationTitle(model.mediaURL?.lastPathComponent ?? "Yogurt")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.insertTimestamp()
                } label: {
                    Label("Insert Timestamp", systemImage: "clock.badge.checkmark")
                }
                .help("Insert current playback time into notes (⌘T)")
                .disabled(model.mediaURL == nil)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    DispatchQueue.main.async {
                        AppModel.shared.open(url)
                    }
                }
            }
            return true
        }
    }
}

private struct NotesPane: View {
    @ObservedObject var notes: NotesStore
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
            NotesEditor(
                text: Binding(
                    get: { notes.text },
                    set: { newValue in
                        notes.text = newValue
                        notes.noteChanged()
                    }
                ),
                onSeek: onSeek
            )
        }
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.square.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a media file to start taking notes")
                .foregroundStyle(.secondary)
            Button("Open… (⌘O)") {
                model.openPanel()
            }
            Text("or drop a file here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
