import AppKit
import Highlightr

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

    /// Left/right paragraph indent — body text starts here, heading # signs hang to the left of it.
    /// Sized to fit the widest prefix "###### " (7 monospace chars) so all levels trail-align.
    var textMargin: CGFloat {
        let charWidth = ("#" as NSString).size(withAttributes: [.font: prefs.font]).width
        return ceil(charWidth * 7)
    }

    private var baseParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 12
        style.paragraphSpacing = 12
        style.headIndent = textMargin
        style.firstLineHeadIndent = textMargin
        style.tailIndent = -textMargin
        return style
    }

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
        let font = prefs.font
        let paraStyle = baseParagraphStyle

        // Base attributes
        styled.setAttributes([
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paraStyle
        ], range: fullRange)

        // Determine paragraph type
        let isInFenced = fencedCodeTracker?.isInsideFencedCode(paragraphLocation: range.location) ?? false
        let element = MarkdownPatterns.paragraphType(for: line, isInFencedCode: isInFenced)

        // Apply block-level style
        applyBlockStyle(element, to: styled, fullRange: fullRange, font: font, paraStyle: paraStyle,
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
        paraStyle: NSParagraphStyle,
        documentRange: NSRange,
        textStorage: NSTextStorage
    ) {
        switch element {
        case .heading(let level):
            let headingFont = prefs.boldFont
            let headingStyle = paraStyle.mutableCopy() as! NSMutableParagraphStyle
            headingStyle.paragraphSpacingBefore = 16
            headingStyle.paragraphSpacing = 6
            // Trail-align: "# " prefix ends exactly at textMargin
            let margin = textMargin
            let prefixStr = String(repeating: "#", count: level) + " "
            let prefixWidth = ceil((prefixStr as NSString).size(withAttributes: [.font: headingFont]).width)
            headingStyle.firstLineHeadIndent = max(0, margin - prefixWidth)
            headingStyle.headIndent = margin
            headingStyle.tailIndent = -margin
            styled.addAttributes([
                .font: headingFont,
                .paragraphStyle: headingStyle
            ], range: fullRange)
            // Dim the "# " prefix
            let prefixLen = level + 1
            if prefixLen <= fullRange.length {
                styled.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: NSRange(location: 0, length: prefixLen))
            }

        case .blockquote:
            let bqStyle = paraStyle.mutableCopy() as! NSMutableParagraphStyle
            bqStyle.headIndent = textMargin + 20
            bqStyle.firstLineHeadIndent = textMargin + 20
            styled.addAttributes([
                .font: prefs.italicFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: bqStyle
            ], range: fullRange)

        case .fencedCodeFence(_):
            let fenceStyle = paraStyle.mutableCopy() as! NSMutableParagraphStyle
            fenceStyle.headIndent = textMargin + 20
            fenceStyle.firstLineHeadIndent = textMargin + 20
            fenceStyle.tailIndent = -(textMargin + 20)
            fenceStyle.paragraphSpacingBefore = 24
            fenceStyle.paragraphSpacing = 24
            styled.addAttributes([
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: fenceStyle
            ], range: fullRange)

        case .fencedCodeBody:
            let codeStyle = paraStyle.mutableCopy() as! NSMutableParagraphStyle
            codeStyle.headIndent = textMargin + 20
            codeStyle.firstLineHeadIndent = textMargin + 20
            codeStyle.tailIndent = -(textMargin + 20)
            styled.addAttribute(.paragraphStyle, value: codeStyle, range: fullRange)
            applyCodeHighlighting(to: styled, fullRange: fullRange, font: font,
                                  documentRange: documentRange, textStorage: textStorage)

        case .orderedList(let indent), .unorderedList(let indent):
            let listStyle = paraStyle.mutableCopy() as! NSMutableParagraphStyle
            let extraIndent = CGFloat(20 + (indent / 4) * 20)
            listStyle.headIndent = textMargin + extraIndent
            listStyle.firstLineHeadIndent = textMargin + max(0, extraIndent - 20)
            styled.addAttribute(.paragraphStyle, value: listStyle, range: fullRange)

        case .taskList(let checked, let indent):
            let listStyle = paraStyle.mutableCopy() as! NSMutableParagraphStyle
            let extraIndent = CGFloat(20 + (indent / 4) * 20)
            listStyle.headIndent = textMargin + extraIndent
            listStyle.firstLineHeadIndent = textMargin + max(0, extraIndent - 20)
            styled.addAttribute(.paragraphStyle, value: listStyle, range: fullRange)
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
        for match in MarkdownPatterns.boldItalic.matches(in: line, range: fullRange) {
            let matchRange = match.range
            guard !overlapsCode(matchRange, codeRanges: codeRanges) else { continue }
            styled.addAttribute(.font, value: prefs.boldItalicFont, range: matchRange)
        }

        // 3. Bold **text**
        for match in MarkdownPatterns.bold.matches(in: line, range: fullRange) {
            let matchRange = match.range
            guard !overlapsCode(matchRange, codeRanges: codeRanges) else { continue }
            // Skip if part of bold-italic
            if matchRange.length > 4 { continue }
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
