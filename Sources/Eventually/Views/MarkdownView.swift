import SwiftUI

/// Lightweight block-level markdown renderer for task notes.
/// Handles headings (`#`/`##`/`###`), bullet lists (`-`/`*`), horizontal rules
/// (`---`), and inline styling (bold/italic/links) on the remaining lines.
/// SwiftUI's built-in `AttributedString(markdown:)` only does inline, so this
/// fills the gap for headings and lists.
struct MarkdownView: View {
    let text: String
    var baseSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                line(raw)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: [String] { text.components(separatedBy: "\n") }

    @ViewBuilder
    private func line(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if let (level, content) = heading(trimmed) {
            Text(inline(content))
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, 2)
        } else if trimmed == "---" || trimmed == "___" || trimmed == "***" {
            Divider().padding(.vertical, 2)
        } else if let item = bullet(trimmed) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").font(.system(size: baseSize))
                Text(inline(item)).font(.system(size: baseSize))
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 2)
        } else {
            Text(inline(raw)).font(.system(size: baseSize))
        }
    }

    // MARK: - Parsing helpers

    private func heading(_ line: String) -> (Int, String)? {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...3).contains(hashes) else { return nil }
        let content = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (hashes, content)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return baseSize + 5
        case 2:  return baseSize + 3
        default: return baseSize + 1
        }
    }

    private func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }
}

/// Renders plain text with auto-detected clickable URLs.
/// Used for the collapsed notes preview and anywhere markdown isn't needed.
struct LinkedTextView: NSViewRepresentable {
    let text: String
    var font: NSFont = .systemFont(ofSize: 11)
    var textColor: NSColor = .tertiaryLabelColor
    var lineLimit: Int = 1

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.isEditable = false
        field.isSelectable = true
        field.allowsEditingTextAttributes = true  // required for link clicks
        field.backgroundColor = .clear
        field.maximumNumberOfLines = lineLimit
        field.lineBreakMode = lineLimit == 1 ? .byTruncatingTail : .byWordWrapping
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let attributed = NSMutableAttributedString(string: text)
        let range = NSRange(text.startIndex..., in: text)

        // Base style
        attributed.addAttributes([
            .font: font,
            .foregroundColor: textColor
        ], range: range)

        // Detect and link URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        detector?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let url = match.url else { return }
            attributed.addAttributes([
                .link: url,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range)
        }

        field.attributedStringValue = attributed
        field.maximumNumberOfLines = lineLimit
    }
}
