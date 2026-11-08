import AppKit

/// Regex-based markdown styling for the plain-text notes editor. Re-applied on
/// every edit over the whole document — attribute-only changes, so undo and
/// selection are unaffected. Timestamp links are applied last so they always win.
enum MarkdownHighlighter {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Fonts.regular, .foregroundColor: Theme.Notes.body, .paragraphStyle: NSParagraphStyle.default]
    }

    private static let syntaxColor = Theme.Notes.syntax
    private static let accentColor = Theme.Notes.listMarker

    private static func headingColor(level: Int) -> NSColor {
        switch level {
        case 1: return Theme.Notes.heading1
        case 2: return Theme.Notes.heading2
        default: return Theme.Notes.sage
        }
    }

    /// Wrapped lines of a list item line up with its text, not its marker.
    private static func hangingIndent(for prefix: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = (prefix as NSString).size(withAttributes: [.font: Fonts.regular]).width
        return style
    }

    private static let headingStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 8
        return style
    }()

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
    private static let strikeSpan = regex(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
    private static let taskItem = regex(#"^([ \t]*[-*+][ \t])(\[([ xX])\])[ \t](.*)$"#)

    static func highlight(_ storage: NSTextStorage, seekURLScheme: String = "yogurt") {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        storage.removeAttribute(.link, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.removeAttribute(.underlineStyle, range: fullRange)
        storage.removeAttribute(.strikethroughStyle, range: fullRange)
        storage.addAttributes(baseAttributes, range: fullRange)
        let nsText = text as NSString

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
        strikeSpan.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
            let closer = NSRange(location: match.range.upperBound - 2, length: 2)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: closer)
        }
        blockquote.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.font, value: Fonts.italic, range: match.range)
            storage.addAttribute(.foregroundColor, value: Theme.Notes.sage, range: match.range)
        }
        heading.matches(in: text, range: fullRange).forEach { match in
            let level = match.range(at: 1).length
            storage.addAttribute(.font, value: Fonts.heading(level: level), range: match.range)
            storage.addAttribute(.foregroundColor, value: headingColor(level: level), range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
            storage.addAttribute(.paragraphStyle, value: headingStyle, range: nsText.paragraphRange(for: match.range))
        }
        listMarker.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.foregroundColor, value: accentColor, range: match.range(at: 1))
            storage.addAttribute(.paragraphStyle,
                                 value: hangingIndent(for: nsText.substring(with: match.range)),
                                 range: nsText.paragraphRange(for: match.range))
        }
        taskItem.matches(in: text, range: fullRange).forEach { match in
            // Indent wrapped lines past the box too: "- [ ] ".
            let prefix = NSRange(location: match.range.location,
                                 length: match.range(at: 4).location - match.range.location)
            storage.addAttribute(.paragraphStyle,
                                 value: hangingIndent(for: nsText.substring(with: prefix)),
                                 range: nsText.paragraphRange(for: match.range))
            storage.addAttribute(.foregroundColor, value: accentColor, range: match.range(at: 2))
            if nsText.substring(with: match.range(at: 3)) != " " {
                storage.addAttribute(.foregroundColor, value: Theme.Notes.done, range: match.range(at: 4))
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 4))
            }
        }
        mdLink.matches(in: text, range: fullRange).forEach { match in
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
            storage.addAttribute(.foregroundColor, value: Theme.Notes.link, range: match.range(at: 1))
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: Theme.Notes.sage, range: match.range(at: 2))
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
            .foregroundColor: Theme.Notes.body,
            .backgroundColor: Theme.Notes.body.withAlphaComponent(0.07),
        ]
    }
}
