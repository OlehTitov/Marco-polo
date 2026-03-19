import AppKit

final class MarkdownStyling: NSObject, NSTextContentStorageDelegate {
    var fencedCodeTracker: FencedCodeTracker?
    var isFocusModeEnabled = false
    var focusedParagraphLocation: Int?

    /// Left/right paragraph indent — body text starts here, heading # signs hang to the left of it.
    /// Sized to fit the widest prefix "###### " (7 monospace chars) so all levels trail-align.
    private var textMargin: CGFloat {
        let charWidth = ("#" as NSString).size(withAttributes: [.font: prefs.font]).width
        return ceil(charWidth * 7)
    }

    private var prefs: Preferences { Preferences.shared }

    private var baseParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
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
        applyBlockStyle(element, to: styled, fullRange: fullRange, font: font, paraStyle: paraStyle)

        // Apply inline styles (skip inside fenced code body)
        switch element {
        case .fencedCodeBody, .fencedCodeFence:
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
        paraStyle: NSParagraphStyle
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

        case .fencedCodeFence:
            styled.addAttributes([
                .foregroundColor: NSColor.tertiaryLabelColor
            ], range: fullRange)

        case .fencedCodeBody:
            styled.addAttributes([
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: fullRange)

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
            styled.addAttributes([
                .foregroundColor: NSColor.systemOrange,
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: matchRange)
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
