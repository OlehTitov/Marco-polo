import AppKit
import Highlightr

enum EditorTypography {
    static let bodyLineHeightMultiple: CGFloat = 1.38

    private static let blockIndent: CGFloat = 20
    private static let headingSpacingBeforeScale: [CGFloat] = [10, 8, 6, 4, 4, 4]
    private static let headingSpacingAfterScale: [CGFloat] = [6, 4, 3, 2, 2, 2]

    static func font(for element: MarkdownElement, preferences: Preferences) -> NSFont {
        switch element {
        case .heading:
            return preferences.boldFont
        case .blockquote:
            return preferences.italicFont
        default:
            return preferences.font
        }
    }

    static func paragraphStyle(for element: MarkdownElement, preferences: Preferences) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        let margin = TextMetrics.textMargin(for: preferences.font)

        style.lineHeightMultiple = bodyLineHeightMultiple
        style.headIndent = margin
        style.firstLineHeadIndent = margin

        switch element {
        case .heading(let level):
            let headingFont = font(for: element, preferences: preferences)
            let prefix = String(repeating: "#", count: level) + " "
            let prefixWidth = ceil((prefix as NSString).size(withAttributes: [.font: headingFont]).width)

            style.firstLineHeadIndent = max(0, margin - prefixWidth)
            style.paragraphSpacingBefore = headingSpacingBefore(for: level)
            style.paragraphSpacing = headingSpacingAfter(for: level)

        case .blockquote:
            style.headIndent = margin + blockIndent
            style.firstLineHeadIndent = margin + blockIndent

        case .fencedCodeFence(_), .fencedCodeBody:
            style.headIndent = margin + blockIndent
            style.firstLineHeadIndent = margin + blockIndent
            style.tailIndent = -(margin + blockIndent)

        case .orderedList(let indent), .unorderedList(let indent), .taskList(_, let indent):
            let nestingLevel = CGFloat(indent / 4)
            let extraIndent = blockIndent + (nestingLevel * blockIndent)
            style.headIndent = margin + extraIndent
            style.firstLineHeadIndent = margin + max(0, extraIndent - blockIndent)

        case .horizontalRule:
            style.paragraphSpacingBefore = 6
            style.paragraphSpacing = 6

        case .plain:
            break
        }

        return style
    }

    static func fallbackCaretHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private static func headingSpacingBefore(for level: Int) -> CGFloat {
        headingSpacingBeforeScale[clampedHeadingIndex(for: level)]
    }

    private static func headingSpacingAfter(for level: Int) -> CGFloat {
        headingSpacingAfterScale[clampedHeadingIndex(for: level)]
    }

    private static func clampedHeadingIndex(for level: Int) -> Int {
        min(max(level, 1), 6) - 1
    }
}

final class MarkdownStyling: NSObject, NSTextContentStorageDelegate {
    var fencedCodeTracker: FencedCodeTracker?
    var isFocusModeEnabled = false
    var focusedParagraphLocation: Int?

    // MARK: - Highlightr

    private lazy var highlightr: Highlightr? = {
        let h = Highlightr()
        let theme = currentThemeName
        h?.setTheme(to: theme)
        self.appliedThemeName = theme
        return h
    }()

    /// Cache keyed by open fence location → highlighted NSAttributedString of the full code block
    private var highlightCache: [Int: NSAttributedString] = [:]
    private var appliedThemeName: String?

    private var currentThemeName: String {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? "atom-one-dark" : "atom-one-light"
    }

    func clearHighlightCache() {
        highlightCache.removeAll()
    }

    func updateThemeIfNeeded() {
        let name = currentThemeName
        guard name != appliedThemeName else { return }
        highlightr?.setTheme(to: name)
        appliedThemeName = name
        clearHighlightCache()
    }

    private var prefs: Preferences { Preferences.shared }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let textStorage = textContentStorage.textStorage,
              let originalText = textStorage.attributedSubstring(from: range) as NSAttributedString? else {
            return nil
        }

        let line = originalText.string
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let styled = NSMutableAttributedString(string: line)

        let isInFenced = fencedCodeTracker?.isInsideFencedCode(paragraphLocation: range.location) ?? false
        let element = MarkdownPatterns.paragraphType(for: line, isInFencedCode: isInFenced)
        let font = EditorTypography.font(for: element, preferences: prefs)
        let paraStyle = EditorTypography.paragraphStyle(for: element, preferences: prefs)

        // Base attributes
        styled.setAttributes([
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paraStyle
        ], range: fullRange)

        // Apply block-level style
        applyBlockStyle(element, to: styled, fullRange: fullRange, font: font,
                        documentRange: range, textStorage: textStorage)

        // Apply inline styles (skip inside fenced code body)
        switch element {
        case .fencedCodeBody, .fencedCodeFence(_):
            break
        default:
            applyInlineStyles(to: styled, line: line, fullRange: fullRange, font: font)
        }

        // Focus mode dimming
        if isFocusModeEnabled {
            let isFocused = isFocusedParagraph(range: range)
            if !isFocused {
                styled.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: fullRange)
            }
        }

        return NSTextParagraph(attributedString: styled)
    }

    // MARK: - Block-level styling

    private func applyBlockStyle(
        _ element: MarkdownElement,
        to styled: NSMutableAttributedString,
        fullRange: NSRange,
        font: NSFont,
        documentRange: NSRange,
        textStorage: NSTextStorage
    ) {
        switch element {
        case .heading(let level):
            let prefixLen = level + 1
            if prefixLen <= fullRange.length {
                styled.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor,
                                    range: NSRange(location: 0, length: prefixLen))
            }

        case .blockquote:
            styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullRange)

        case .fencedCodeFence(_):
            styled.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: fullRange)

        case .fencedCodeBody:
            applyCodeHighlighting(to: styled, fullRange: fullRange, font: font,
                                  documentRange: documentRange, textStorage: textStorage)

        case .orderedList, .unorderedList:
            break

        case .taskList(let checked, _):
            if checked {
                styled.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ], range: fullRange)
            }

        case .horizontalRule:
            styled.addAttribute(.foregroundColor, value: NSColor.separatorColor, range: fullRange)

        case .plain:
            break
        }
    }

    // MARK: - Code block highlighting

    private func applyCodeHighlighting(
        to styled: NSMutableAttributedString,
        fullRange: NSRange,
        font: NSFont,
        documentRange: NSRange,
        textStorage: NSTextStorage
    ) {
        guard let tracker = fencedCodeTracker,
              let info = tracker.codeBlockInfo(forParagraphAt: documentRange.location),
              info.codeRange.length > 0,
              let highlightr else {
            // Fall back to default grey
            styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullRange)
            return
        }

        let cacheKey = info.openLocation

        // Get or create cached highlighted string for the whole code block
        if highlightCache[cacheKey] == nil {
            let codeText = textStorage.attributedSubstring(from: info.codeRange).string
            if let highlighted = highlightr.highlight(codeText, as: info.language) {
                highlightCache[cacheKey] = highlighted
            }
        }

        guard let cached = highlightCache[cacheKey] else {
            styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullRange)
            return
        }

        // Compute this paragraph's offset within the code block
        let offsetInBlock = documentRange.location - info.codeRange.location
        let cachedString = cached.string as NSString
        let cachedLength = cachedString.length

        guard offsetInBlock >= 0, offsetInBlock < cachedLength else {
            styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullRange)
            return
        }

        // The paragraph length in the cached string (may differ slightly due to trailing newline)
        let availableLength = min(fullRange.length, cachedLength - offsetInBlock)
        guard availableLength > 0 else {
            styled.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullRange)
            return
        }

        let sourceRange = NSRange(location: offsetInBlock, length: availableLength)

        // Copy foreground color attributes from the highlighted string
        cached.enumerateAttribute(.foregroundColor, in: sourceRange) { value, attrRange, _ in
            guard let color = value as? NSColor else { return }
            let localRange = NSRange(location: attrRange.location - offsetInBlock, length: attrRange.length)
            guard localRange.location >= 0, NSMaxRange(localRange) <= fullRange.length else { return }
            styled.addAttribute(.foregroundColor, value: color, range: localRange)
        }

        // Override font to match our monospace preference
        styled.addAttribute(.font, value: font, range: fullRange)
    }

    // MARK: - Inline styling

    private func applyInlineStyles(
        to styled: NSMutableAttributedString,
        line: String,
        fullRange: NSRange,
        font: NSFont
    ) {
        // Collect code span ranges to protect them from other patterns
        var codeRanges: [NSRange] = []

        // 1. Inline code (first, to protect from other patterns)
        for match in MarkdownPatterns.inlineCode.matches(in: line, range: fullRange) {
            let matchRange = match.range
            styled.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: matchRange)
            codeRanges.append(matchRange)
        }

        // 2. Bold-italic ***text***
        var boldItalicRanges: [NSRange] = []
        for match in MarkdownPatterns.boldItalic.matches(in: line, range: fullRange) {
            let matchRange = match.range
            guard !overlapsCode(matchRange, codeRanges: codeRanges) else { continue }
            styled.addAttribute(.font, value: prefs.boldItalicFont, range: matchRange)
            boldItalicRanges.append(matchRange)
        }

        // 3. Bold **text**
        for match in MarkdownPatterns.bold.matches(in: line, range: fullRange) {
            let matchRange = match.range
            guard !overlapsCode(matchRange, codeRanges: codeRanges) else { continue }
            guard !overlapsCode(matchRange, codeRanges: boldItalicRanges) else { continue }
            styled.addAttribute(.font, value: prefs.boldFont, range: matchRange)
        }

        // 4. Italic *text*
        for match in MarkdownPatterns.italic.matches(in: line, range: fullRange) {
            let matchRange = match.range
            guard !overlapsCode(matchRange, codeRanges: codeRanges) else { continue }
            styled.addAttribute(.font, value: prefs.italicFont, range: matchRange)
        }

        // 5. Strikethrough ~~text~~
        for match in MarkdownPatterns.strikethrough.matches(in: line, range: fullRange) {
            let matchRange = match.range
            guard !overlapsCode(matchRange, codeRanges: codeRanges) else { continue }
            styled.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: matchRange)
        }

        // 6. Links [text](url)
        for match in MarkdownPatterns.link.matches(in: line, range: fullRange) {
            guard !overlapsCode(match.range, codeRanges: codeRanges) else { continue }
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            // Style the bracket/paren delimiters + url as dim
            styled.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range)
            // Style the text portion as link
            styled.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textRange)
            // URL stays dim (already set on full range)
            _ = urlRange
        }
    }

    private func overlapsCode(_ range: NSRange, codeRanges: [NSRange]) -> Bool {
        for codeRange in codeRanges {
            if NSIntersectionRange(range, codeRange).length > 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Focus mode

    private func isFocusedParagraph(range: NSRange) -> Bool {
        guard let focusLoc = focusedParagraphLocation else { return true }
        return range.location == focusLoc
    }

}
