import AppKit

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

        case .orderedList(let indent), .unorderedList(let indent), .taskList(_, let indent):
            let nestingLevel = CGFloat(indent / 4)
            let extraIndent = blockIndent + (nestingLevel * blockIndent)
            style.headIndent = margin + extraIndent
            style.firstLineHeadIndent = margin + max(0, extraIndent - blockIndent)

        case .horizontalRule:
            style.paragraphSpacingBefore = 6
            style.paragraphSpacing = 6

        case .fencedCodeFence(_), .fencedCodeBody, .plain:
            break

        }

        return style
    }

    static func fallbackCaretHeight(for font: NSFont) -> CGFloat {
        fixedLineHeight(for: font)
    }

    static func fixedLineHeight(for font: NSFont) -> CGFloat {
        let textHeight = ceil(font.ascender - font.descender)
        return ceil(textHeight * bodyLineHeightMultiple)
    }

    static func normalizedLineHeightMultiple(for paragraphStyle: NSParagraphStyle?) -> CGFloat {
        let multiple = paragraphStyle?.lineHeightMultiple ?? 0
        return multiple > 0 ? multiple : 1.0
    }

    static func lineFragmentDrawOffset(for lineFragment: NSTextLineFragment, paragraphStyle: NSParagraphStyle?) -> CGFloat {
        -(lineFragment.typographicBounds.height * (normalizedLineHeightMultiple(for: paragraphStyle) - 1.0) / 2.0)
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

private final class EditorTextLayoutFragment: NSTextLayoutFragment {
    private let defaultParagraphStyle: NSParagraphStyle

    init(textElement: NSTextElement, range rangeInElement: NSTextRange?, defaultParagraphStyle: NSParagraphStyle) {
        self.defaultParagraphStyle = defaultParagraphStyle
        super.init(textElement: textElement, range: rangeInElement)
    }

    required init?(coder: NSCoder) {
        self.defaultParagraphStyle = NSParagraphStyle.default
        super.init(coder: coder)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        guard state.rawValue >= NSTextLayoutFragment.State.layoutAvailable.rawValue else {
            super.draw(at: point, in: context)
            return
        }

        context.saveGState()

        for lineFragment in textLineFragments {
            let paragraphStyle: NSParagraphStyle
            if lineFragment.attributedString.length > 0,
               let lineParagraphStyle = lineFragment.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                paragraphStyle = lineParagraphStyle
            } else {
                paragraphStyle = defaultParagraphStyle
            }

            let offset = EditorTypography.lineFragmentDrawOffset(for: lineFragment, paragraphStyle: paragraphStyle)
            lineFragment.draw(
                at: CGPoint(
                    x: point.x + lineFragment.typographicBounds.origin.x,
                    y: point.y + lineFragment.typographicBounds.origin.y + offset
                ),
                in: context
            )
        }

        context.restoreGState()
    }
}

final class MarkdownStyling: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    var fencedCodeTracker: FencedCodeTracker?
    var isFocusModeEnabled = false
    var focusedParagraphLocation: Int?
    var currentAppearance: NSAppearance = NSApp.effectiveAppearance

    private var prefs: Preferences { Preferences.shared }

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let originalText = textContentStorage.textStorage?.attributedSubstring(from: range) as NSAttributedString? else {
            return nil
        }

        let line = originalText.string
        let nsLine = line as NSString
        let fullRange = NSRange(location: 0, length: nsLine.length)
        let styled = NSMutableAttributedString(string: line)
        let palette = prefs.themePalette(for: currentAppearance)

        let isInFenced = fencedCodeTracker?.isInsideFencedCode(paragraphLocation: range.location) ?? false
        let element = MarkdownPatterns.paragraphType(for: line, isInFencedCode: isInFenced)
        let font = EditorTypography.font(for: element, preferences: prefs)
        let paraStyle = EditorTypography.paragraphStyle(for: element, preferences: prefs)

        // Base attributes
        styled.setAttributes([
            .font: font,
            .foregroundColor: palette.editorText,
            .paragraphStyle: paraStyle
        ], range: fullRange)

        // Apply block-level style
        applyBlockStyle(element, to: styled, fullRange: fullRange, palette: palette)

        // Apply inline styles (skip inside fenced code body)
        switch element {
        case .fencedCodeBody, .fencedCodeFence(_):
            break
        default:
            applyInlineStyles(to: styled, line: line, fullRange: fullRange, palette: palette)
        }

        // Focus mode dimming
        if isFocusModeEnabled {
            let isFocused = isFocusedParagraph(range: range)
            if !isFocused {
                styled.addAttribute(.foregroundColor, value: palette.subduedText, range: fullRange)
            }
        }

        return NSTextParagraph(attributedString: styled)
    }

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        EditorTextLayoutFragment(
            textElement: textElement,
            range: textElement.elementRange,
            defaultParagraphStyle: EditorTypography.paragraphStyle(for: .plain, preferences: prefs)
        )
    }

    // MARK: - Block-level styling

    private func applyBlockStyle(
        _ element: MarkdownElement,
        to styled: NSMutableAttributedString,
        fullRange: NSRange,
        palette: EditorThemePalette
    ) {
        switch element {
        case .heading(let level):
            let prefixLen = level + 1
            if prefixLen <= fullRange.length {
                styled.addAttribute(.foregroundColor, value: palette.tertiaryText,
                                    range: NSRange(location: 0, length: prefixLen))
            }

        case .blockquote:
            styled.addAttribute(.foregroundColor, value: palette.secondaryText, range: fullRange)

        case .fencedCodeFence(_):
            styled.addAttribute(.foregroundColor, value: palette.inlineCodeText, range: fullRange)

        case .fencedCodeBody:
            styled.addAttribute(.foregroundColor, value: palette.inlineCodeText, range: fullRange)

        case .orderedList, .unorderedList:
            break

        case .taskList(let checked, _):
            if checked {
                styled.addAttributes([
                    .foregroundColor: palette.secondaryText,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue
                ], range: fullRange)
            }

        case .horizontalRule:
            styled.addAttribute(.foregroundColor, value: palette.separator, range: fullRange)

        case .plain:
            break
        }
    }

    // MARK: - Inline styling

    private func applyInlineStyles(
        to styled: NSMutableAttributedString,
        line: String,
        fullRange: NSRange,
        palette: EditorThemePalette
    ) {
        // Collect code span ranges to protect them from other patterns
        var codeRanges: [NSRange] = []

        // 1. Inline code (first, to protect from other patterns)
        for match in MarkdownPatterns.inlineCode.matches(in: line, range: fullRange) {
            let matchRange = match.range
            styled.addAttribute(.foregroundColor, value: palette.inlineCodeText, range: matchRange)
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
                .foregroundColor: palette.secondaryText,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ], range: matchRange)
        }

        // 6. Links [text](url)
        for match in MarkdownPatterns.link.matches(in: line, range: fullRange) {
            guard !overlapsCode(match.range, codeRanges: codeRanges) else { continue }
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            // Style the bracket/paren delimiters + url as dim
            styled.addAttribute(.foregroundColor, value: palette.tertiaryText, range: match.range)
            // Style the text portion as link
            styled.addAttributes([
                .foregroundColor: palette.linkText,
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
