import AppKit

enum MarkdownElement {
    case heading(Int)
    case blockquote
    case orderedList(indent: Int)
    case unorderedList(indent: Int)
    case taskList(checked: Bool, indent: Int)
    case horizontalRule
    case fencedCodeFence(language: String?)
    case fencedCodeBody
    case plain
}

struct MarkdownPatterns {
    // MARK: - Inline patterns (compiled once)

    static let boldItalic = try! NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*")
    static let bold = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    static let italic = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
    static let strikethrough = try! NSRegularExpression(pattern: "~~(.+?)~~")
    static let inlineCode = try! NSRegularExpression(pattern: "`([^`]+)`")
    static let link = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")

    // MARK: - Block-level prefix patterns

    private static let headingPattern = try! NSRegularExpression(pattern: "^(#{1,6})\\s")
    private static let blockquotePattern = try! NSRegularExpression(pattern: "^(\\s*>)+\\s?")
    private static let orderedListPattern = try! NSRegularExpression(pattern: "^(\\s*)\\d+\\.\\s")
    private static let unorderedListPattern = try! NSRegularExpression(pattern: "^(\\s*)[-*+]\\s")
    private static let taskListPattern = try! NSRegularExpression(pattern: "^(\\s*)- \\[([ x])\\]\\s")
    private static let horizontalRulePattern = try! NSRegularExpression(pattern: "^(---+|\\*\\*\\*+|___+)\\s*$")
    private static let fencedCodeFencePattern = try! NSRegularExpression(pattern: "^```(\\w+)?\\s*$")

    // MARK: - Paragraph type detection

    static func paragraphType(for line: String, isInFencedCode: Bool) -> MarkdownElement {
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)

        // Check for fenced code fence first
        if let match = fencedCodeFencePattern.firstMatch(in: line, range: fullRange) {
            let langRange = match.range(at: 1)
            let language: String? = langRange.location != NSNotFound ? nsLine.substring(with: langRange) : nil
            return .fencedCodeFence(language: language)
        }

        // If inside fenced code, everything is body
        if isInFencedCode {
            return .fencedCodeBody
        }

        // Heading
        if let match = headingPattern.firstMatch(in: line, range: fullRange) {
            let level = match.range(at: 1).length
            return .heading(level)
        }

        // Task list (must check before unordered list)
        if let match = taskListPattern.firstMatch(in: line, range: fullRange) {
            let indent = match.range(at: 1).length
            let checkChar = nsLine.substring(with: match.range(at: 2))
            return .taskList(checked: checkChar == "x", indent: indent)
        }

        // Unordered list
        if let match = unorderedListPattern.firstMatch(in: line, range: fullRange) {
            let indent = match.range(at: 1).length
            return .unorderedList(indent: indent)
        }

        // Ordered list
        if let match = orderedListPattern.firstMatch(in: line, range: fullRange) {
            let indent = match.range(at: 1).length
            return .orderedList(indent: indent)
        }

        // Horizontal rule
        if horizontalRulePattern.firstMatch(in: line, range: fullRange) != nil {
            return .horizontalRule
        }

        // Blockquote
        if blockquotePattern.firstMatch(in: line, range: fullRange) != nil {
            return .blockquote
        }

        return .plain
    }

    // MARK: - Heading helpers

    static func headingLevel(for line: String) -> Int {
        var count = 0
        for character in line {
            if character == "#" {
                count += 1
            } else {
                break
            }
        }
        guard count > 0, count <= 6 else { return 0 }
        let index = line.index(line.startIndex, offsetBy: count, limitedBy: line.endIndex) ?? line.endIndex
        return index < line.endIndex && line[index] == " " ? count : 0
    }

}
