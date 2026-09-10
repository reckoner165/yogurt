import AppKit

/// Regex-based markdown styling for the plain-text notes editor. Re-applied on
/// every edit over the whole document — attribute-only changes, so undo and
/// selection are unaffected. Timestamp links are applied last so they always win.
enum MarkdownHighlighter {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Fonts.regular, .foregroundColor: NSColor.textColor]
    }

    private static let syntaxColor = NSColor.tertiaryLabelColor
    private static let accentColor = NSColor.controlAccentColor

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let heading = regex(#"^(#{1,6})[ \t](.*)$"#)
    private static let blockquote = regex(#"^>[ \t]?.*$"#)
    private static let listMarker = regex(#"^[ \t]*([-*+]|\d+\.)[ \t]"#)
    private static let boldSpan = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicSpan = regex(#"(?<![*\w])(\*|_)(?![*_\s])([^*_\n]+?)(?<![*_\s])\1(?![*\w])"#)
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let codeFence = regex(#"^```[^\n]*\n[\s\S]*?^```[ \t]*$"#)
    private static let mdLink = regex(#"\[([^\]\n]*)\]\(([^)\n]*)\)"#)

    static func highlight(_ storage: NSTextStorage, seekURLScheme: String = "yogurt") {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.removeAttribute(.link, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.addAttributes(baseAttributes, range: fullRange)

        italicSpan.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.font, value: Fonts.italic, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
            let closer = NSRange(location: match.range.upperBound - match.range(at: 1).length,
                                 length: match.range(at: 1).length)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: closer)
        }
        boldSpan.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.font, value: Fonts.bold, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
            let closer = NSRange(location: match.range.upperBound - 2, length: 2)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: closer)
        }
        blockquote.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.font, value: Fonts.italic, range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        }
        heading.matches(in: text, range: fullRange).forEach { match in
            let level = match.range(at: 1).length
            storage.addAttribute(.font, value: Fonts.heading(level: level), range: match.range)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
        }
        listMarker.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.foregroundColor, value: accentColor, range: match.range(at: 1))
        }
        mdLink.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 2))
        }
        codeFence.matches(in: text, range: fullRange).forEach { match in
            storage.addAttributes(codeAttributes, range: match.range)
        }
        inlineCode.matches(in: text, range: fullRange).forEach { match in
            storage.addAttributes(codeAttributes, range: match.range)
        }

        NotesEditor.timestampRegex.matches(in: text, range: fullRange).forEach { match in
            let seconds = NotesEditor.Coordinator.seconds(from: match, in: text)
            if let url = URL(string: "\(seekURLScheme)://seek?t=\(seconds)") {
                storage.addAttribute(.link, value: url, range: match.range)
                storage.addAttribute(.font, value: Fonts.regular, range: match.range)
            }
        }
        storage.endEditing()
    }

    private static var codeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: Fonts.regular,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.textColor.withAlphaComponent(0.07),
        ]
    }
}
