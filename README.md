# Yogurt

A lightweight macOS media player that pairs any media file with timestamped markdown notes.

- Open any Apple-native media file (mp4, mov, m4v, m4a, mp3, wav, aiff, …) and play it with standard controls.
- Take unlimited notes alongside the player. Notes autosave as you type.
- Timestamps like `[3:07]` or `[1:02:45]` are clickable and seek the player. Press **⌘T** to insert the current playback time.
- Notes are plain markdown, stored next to your media at `notes/<filename>.<ext>.md`. An existing `notes/` folder is reused. The media file itself is never modified.

## Building

Requires macOS 13+ and the Xcode Command Line Tools (full Xcode not needed):

```sh
git clone <repo-url> yogurt && cd yogurt
./Scripts/make-app.sh    # produces Yogurt.app
```

During development, `swift run` launches the app directly.

Options for `make-app.sh`:

- `UNIVERSAL=1` — build a universal (arm64 + x86_64) binary.
- `SIGN_IDENTITY="Developer ID Application: …"` — sign with a real identity and the hardened runtime (for notarized releases). Without it the app is ad-hoc signed, which is fine for local use.

## Downloaded builds

Until notarized releases exist, macOS will quarantine a downloaded build. Clear it with:

```sh
xattr -d com.apple.quarantine Yogurt.app
```

## License

MIT — see [LICENSE](LICENSE).
