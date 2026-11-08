import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Without a view above it, HSplitView runs up under the transparent title bar.
            Divider()
            Group {
                if model.mediaURL != nil {
                    HSplitView {
                        PlayerView(player: model.player.player)
                            .frame(minWidth: 320, minHeight: 240)
                            .background {
                                if let backdrop = Theme.playerBackdrop {
                                    Image(nsImage: backdrop)
                                        .resizable()
                                        .scaledToFill()
                                        .blur(radius: 6, opaque: true)
                                        .clipped()
                                }
                            }
                        if model.showMeter {
                            VUMeterView(meter: model.player.meter)
                                .frame(minWidth: 96, idealWidth: 110, maxWidth: 160)
                        }
                        NotesPane(
                            notes: model.notes,
                            mediaInfo: model.mediaInfo,
                            onInsertInfo: { model.insertMediaInfo() },
                            onHint: { model.status.hint($0) },
                            onSeek: { model.seek(to: $0) },
                            onHoverTimestamp: { seconds in
                                model.status.hint(seconds.map {
                                    "Click to jump to \(PlayerController.format($0))"
                                })
                            }
                        )
                        .frame(minWidth: 260)
                        // Header and File Info match the always-dark editor.
                        .environment(\.colorScheme, .dark)
                    }
                } else {
                    EmptyStateView()
                }
            }
            Divider()
            StatusBarView(status: model.status)
        }
        .frame(minWidth: 700, minHeight: 400)
        .background(WindowBackdrop().ignoresSafeArea())
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
                .onHover { hovering in
                    model.status.hint(
                        hovering ? "Insert current playback time into notes (⌘T)" : nil
                    )
                }

                Button {
                    model.toggleMeter()
                } label: {
                    Label(
                        "Audio Meter",
                        systemImage: model.showMeter ? "waveform.circle.fill" : "waveform"
                    )
                }
                .help("Toggle stereo audio meter (⌘L)")
                .disabled(model.mediaURL == nil)
                .onHover { hovering in
                    model.status.hint(
                        hovering ? "Toggle stereo audio meter (⌘L)" : nil
                    )
                }
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
    let mediaInfo: MediaInfoStore
    let onInsertInfo: () -> Void
    let onHint: (String?) -> Void
    let onSeek: (Double) -> Void
    let onHoverTimestamp: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Don't let the colour run up under the transparent title bar.
                .background(Theme.notesSurface, ignoresSafeAreaEdges: [])
            Divider()
            NotesEditor(
                text: Binding(
                    get: { notes.text },
                    set: { newValue in
                        notes.text = newValue
                        notes.noteChanged()
                    }
                ),
                onSeek: onSeek,
                onHoverTimestamp: onHoverTimestamp
            )
            Divider()
            MediaInfoPanel(store: mediaInfo, onInsert: onInsertInfo, onHint: onHint)
        }
    }
}

/// Collapsible file details under the notes, with a button that copies them
/// into the notes as a markdown list.
private struct MediaInfoPanel: View {
    @ObservedObject var store: MediaInfoStore
    let onInsert: () -> Void
    let onHint: (String?) -> Void
    @AppStorage("showMediaInfo") private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("File Info")
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide file info" : "Show file info")

                if store.isMeasuringLevels {
                    ProgressView()
                        .controlSize(.mini)
                        .help("Measuring levels…")
                }
                Spacer()
                Button(action: onInsert) {
                    Image(systemName: "text.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Add file info to notes")
                .onHover { onHint($0 ? "Add file info to notes" : nil) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            if isExpanded {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 3) {
                    ForEach(store.info.rows) { row in
                        GridRow {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            Text(row.value)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }
}

private struct StatusBarView: View {
    @ObservedObject var status: StatusCenter

    var body: some View {
        HStack {
            Text(status.display)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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
