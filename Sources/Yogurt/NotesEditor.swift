import SwiftUI
import AppKit

extension Notification.Name {
    static let yogurtInsertText = Notification.Name("YogurtInsertText")
}

/// Plain-text markdown editor (NSTextView) that turns timestamps like [3:07]
/// or [1:02:45.5] into clickable links that seek the player.
struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    var onSeek: (Double) -> Void

    static let timestampRegex = try! NSRegularExpression(
        pattern: #"\[(?:(\d+):)?(\d{1,2}):(\d{2})(?:\.(\d+))?\]"#
    )

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        context.coordinator.textView = textView
        textView.string = text
        context.coordinator.applyHighlighting()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlighting()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor
        weak var textView: NSTextView?
        private var insertObserver: NSObjectProtocol?

        private let baseFont = NSFont.systemFont(ofSize: 13)

        init(_ parent: NotesEditor) {
            self.parent = parent
            super.init()
            insertObserver = NotificationCenter.default.addObserver(
                forName: .yogurtInsertText, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let snippet = notification.userInfo?["text"] as? String,
                      let textView = self.textView else { return }
                textView.insertText(snippet, replacementRange: textView.selectedRange())
                textView.window?.makeFirstResponder(textView)
            }
        }

        deinit {
            if let insertObserver {
                NotificationCenter.default.removeObserver(insertObserver)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            applyHighlighting()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "yogurt",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let value = components.queryItems?.first(where: { $0.name == "t" })?.value,
                  let seconds = Double(value) else { return false }
            parent.onSeek(seconds)
            return true
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
            ]
            storage.beginEditing()
            storage.removeAttribute(.link, range: fullRange)
            storage.addAttributes(baseAttributes, range: fullRange)
            let matches = NotesEditor.timestampRegex.matches(in: storage.string, range: fullRange)
            for match in matches {
                let seconds = Self.seconds(from: match, in: storage.string)
                if let url = URL(string: "yogurt://seek?t=\(seconds)") {
                    storage.addAttribute(.link, value: url, range: match.range)
                }
            }
            storage.endEditing()
            // Keep typing after a timestamp from inheriting the link style.
            textView.typingAttributes = baseAttributes
        }

        static func seconds(from match: NSTextCheckingResult, in string: String) -> Double {
            func group(_ index: Int) -> String? {
                guard let range = Range(match.range(at: index), in: string) else { return nil }
                return String(string[range])
            }
            let hours = Double(group(1) ?? "") ?? 0
            let minutes = Double(group(2) ?? "") ?? 0
            let seconds = Double(group(3) ?? "") ?? 0
            let fraction = Double("0.\(group(4) ?? "0")") ?? 0
            return hours * 3600 + minutes * 60 + seconds + fraction
        }
    }
}
