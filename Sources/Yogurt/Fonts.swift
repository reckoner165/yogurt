import AppKit

/// Registers the bundled IBM Plex Mono faces for this process and vends them
/// with a system-monospace fallback if registration fails.
enum Fonts {
    static let size: CGFloat = 13

    static func registerBundled() {
        var candidates: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts") {
            candidates.append(bundled)
        }
        // Bare binary during development (swift run / .build/app/Yogurt):
        // fonts live at <repo>/Resources/Fonts relative to the executable.
        if let exe = Bundle.main.executableURL {
            candidates.append(
                exe.deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources/Fonts")
            )
        }
        for dir in candidates {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for url in files where url.pathExtension.lowercased() == "ttf" {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            if !files.isEmpty { break }
        }
    }

    private static func font(_ name: String, fallbackWeight: NSFont.Weight, italic: Bool = false) -> NSFont {
        if let font = NSFont(name: name, size: size) { return font }
        var font = NSFont.monospacedSystemFont(ofSize: size, weight: fallbackWeight)
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    static let regular = font("IBMPlexMono", fallbackWeight: .regular)
    static let bold = font("IBMPlexMono-Bold", fallbackWeight: .bold)
    static let italic = font("IBMPlexMono-Italic", fallbackWeight: .regular, italic: true)
    static let boldItalic = font("IBMPlexMono-BoldItalic", fallbackWeight: .bold, italic: true)

    static func heading(level: Int) -> NSFont {
        let headingSize: CGFloat = level == 1 ? 17 : (level == 2 ? 15 : size)
        if let font = NSFont(name: "IBMPlexMono-Bold", size: headingSize) { return font }
        return NSFont.monospacedSystemFont(ofSize: headingSize, weight: .bold)
    }
}
