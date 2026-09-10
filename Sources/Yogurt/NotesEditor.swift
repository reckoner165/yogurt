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
    var onHoverTimestamp: (Double?) -> Void

    static let timestampRegex = try! NSRegularExpression(
        pattern: #"\[(?:(\d+):)?(\d{1,2}):(\d{2})(?:\.(\d+))?\]"#
    )

    static func seekSeconds(from url: URL) -> Double? {
        guard url.scheme == "yogurt",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "t" })?.value
        else { return nil }
        return Double(value)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NotesTextView()
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

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
        textView.onHoverLink = { [weak coordinator = context.coordinator] url in
            coordinator?.reportHover(url)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

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
        private var lastHoverSeconds: Double?

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
            guard let url = link as? URL, let seconds = NotesEditor.seekSeconds(from: url) else {
                return false
            }
            parent.onSeek(seconds)
            return true
        }

        func reportHover(_ url: URL?) {
            let seconds = url.flatMap(NotesEditor.seekSeconds(from:))
            guard seconds != lastHoverSeconds else { return }
            lastHoverSeconds = seconds
            parent.onHoverTimestamp(seconds)
        }

        func applyHighlighting() {
            guard let textView, let storage = textView.textStorage else { return }
            MarkdownHighlighter.highlight(storage)
            // Keep typing after a styled span from inheriting its attributes.
            textView.typingAttributes = MarkdownHighlighter.baseAttributes
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

/// NSTextView that reports which link (if any) is under the mouse.
final class NotesTextView: NSTextView {
    var onHoverLink: ((URL?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where (area.userInfo?["yogurtHover"] as? Bool) == true {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: ["yogurtHover": true]
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverLink?(linkURL(at: event))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverLink?(nil)
    }

    private func linkURL(at event: NSEvent) -> URL? {
        guard let layoutManager, let textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        guard index < storage.length else { return nil }
        return storage.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
}
