import AppKit

struct MarkdownExporter {

    // MARK: - HTML export

    static func toHTML(_ markdown: String) -> String {
        var html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        body { font-family: -apple-system, system-ui, sans-serif; max-width: 720px; margin: 40px auto; padding: 0 20px; line-height: 1.6; color: #333; }
        pre { background: #f5f5f5; padding: 12px; border-radius: 4px; overflow-x: auto; }
        code { background: #f5f5f5; padding: 2px 4px; border-radius: 3px; font-size: 0.9em; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid #ccc; margin-left: 0; padding-left: 16px; color: #666; }
        hr { border: none; border-top: 1px solid #ccc; margin: 24px 0; }
        img { max-width: 100%; }
        a { color: #0066cc; }
        </style>
        </head><body>
        """

        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var inFencedCode = false
        var inList = false
        var listTag = ""
        var inBlockquote = false

        while i < lines.count {
            let line = lines[i]

            // Fenced code blocks
            if line.hasPrefix("```") {
                if inFencedCode {
                    html += "</code></pre>\n"
                    inFencedCode = false
                } else {
                    inFencedCode = true
                    html += "<pre><code>"
                }
                i += 1
                continue
            }

            if inFencedCode {
                html += escapeHTML(line) + "\n"
                i += 1
                continue
            }

            // Close list if needed
            if inList && !isListLine(line) {
                html += "</\(listTag)>\n"
                inList = false
            }

            // Close blockquote if needed
            if inBlockquote && !line.hasPrefix(">") {
                html += "</blockquote>\n"
                inBlockquote = false
            }

            // Blank line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !inList && !inBlockquote {
                    // Skip blank lines between paragraphs (they're handled by block spacing)
                }
                i += 1
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 && (trimmed.allSatisfy({ $0 == "-" }) || trimmed.allSatisfy({ $0 == "*" }) || trimmed.allSatisfy({ $0 == "_" })) {
                html += "<hr>\n"
                i += 1
                continue
            }

            // Headings
            let headingLevel = MarkdownPatterns.headingLevel(for: line)
            if headingLevel > 0 {
                let content = String(line.dropFirst(headingLevel + 1))
                html += "<h\(headingLevel)>\(inlineToHTML(content))</h\(headingLevel)>\n"
                i += 1
                continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                if !inBlockquote {
                    html += "<blockquote>\n"
                    inBlockquote = true
                }
                var content = line
                if content.hasPrefix("> ") {
                    content = String(content.dropFirst(2))
                } else if content.hasPrefix(">") {
                    content = String(content.dropFirst(1))
                }
                html += "<p>\(inlineToHTML(content))</p>\n"
                i += 1
                continue
            }

            // Lists
            if isListLine(line) {
                let isOrdered = isOrderedListLine(line)
                let tag = isOrdered ? "ol" : "ul"
                if !inList || listTag != tag {
                    if inList { html += "</\(listTag)>\n" }
                    html += "<\(tag)>\n"
                    inList = true
                    listTag = tag
                }
                let content = stripListPrefix(line)
                // Task list
                if let (checked, text) = parseTaskItem(line) {
                    let checkAttr = checked ? " checked disabled" : " disabled"
                    html += "<li><input type=\"checkbox\"\(checkAttr)> \(inlineToHTML(text))</li>\n"
                } else {
                    html += "<li>\(inlineToHTML(content))</li>\n"
                }
                i += 1
                continue
            }

            // Paragraph
            html += "<p>\(inlineToHTML(line))</p>\n"
            i += 1
        }

        // Close open blocks
        if inFencedCode { html += "</code></pre>\n" }
        if inList { html += "</\(listTag)>\n" }
        if inBlockquote { html += "</blockquote>\n" }

        html += "</body></html>"
        return html
    }

    // MARK: - PDF export

    static func toPDF(_ markdown: String) -> Data? {
        let html = toHTML(markdown)
        guard let htmlData = html.data(using: .utf8) else { return nil }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]

        guard let attrString = try? NSAttributedString(data: htmlData, options: options, documentAttributes: nil) else {
            return nil
        }

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72

        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let pageHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        textView.textStorage?.setAttributedString(attrString)
        textView.sizeToFit()

        let data = textView.dataWithPDF(inside: textView.bounds)
        return data
    }

    // MARK: - Inline markdown to HTML

    private static func inlineToHTML(_ text: String) -> String {
        var result = escapeHTML(text)

        // Bold-italic
        result = result.replacingOccurrences(
            of: "\\*\\*\\*(.+?)\\*\\*\\*",
            with: "<strong><em>$1</em></strong>",
            options: .regularExpression
        )
        // Bold
        result = result.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        // Italic
        result = result.replacingOccurrences(
            of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        // Strikethrough
        result = result.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "<del>$1</del>",
            options: .regularExpression
        )
        // Inline code
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )
        // Links
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )

        return result
    }

    // MARK: - Helpers

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func isListLine(_ line: String) -> Bool {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let ul = try! NSRegularExpression(pattern: "^\\s*[-*+]\\s")
        let ol = try! NSRegularExpression(pattern: "^\\s*\\d+\\.\\s")
        return ul.firstMatch(in: line, range: range) != nil || ol.firstMatch(in: line, range: range) != nil
    }

    private static func isOrderedListLine(_ line: String) -> Bool {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let ol = try! NSRegularExpression(pattern: "^\\s*\\d+\\.\\s")
        return ol.firstMatch(in: line, range: range) != nil
    }

    private static func stripListPrefix(_ line: String) -> String {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let pattern = try! NSRegularExpression(pattern: "^\\s*(?:[-*+]|\\d+\\.)\\s")
        if let match = pattern.firstMatch(in: line, range: range) {
            return nsLine.substring(from: NSMaxRange(match.range))
        }
        return line
    }

    private static func parseTaskItem(_ line: String) -> (checked: Bool, text: String)? {
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        let pattern = try! NSRegularExpression(pattern: "^\\s*- \\[([ x])\\]\\s(.*)")
        guard let match = pattern.firstMatch(in: line, range: range) else { return nil }
        let checkChar = nsLine.substring(with: match.range(at: 1))
        let text = nsLine.substring(with: match.range(at: 2))
        return (checkChar == "x", text)
    }
}
