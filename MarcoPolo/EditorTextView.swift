import AppKit

final class EditorTextView: NSTextView {

    var fencedCodeTracker: FencedCodeTracker?
    private var selectionFillColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.26)
    private let geometryLoggingEnabled = true
    private var lastLoggedCursorRect: NSRect = .zero

    // MARK: - Insertion point

    private let cursorWidth: CGFloat = 4
    private var lastCursorRect: NSRect = .zero

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let cursorRect = resolvedInsertionPointRect(from: rect)
        debugLogInsertionGeometryIfNeeded(sourceRect: rect, resolvedRect: cursorRect)

        if lastCursorRect != .zero {
            setNeedsDisplay(lastCursorRect, avoidAdditionalLayout: true)
        }

        if flag {
            color.setFill()
            NSBezierPath(roundedRect: cursorRect, xRadius: cursorWidth / 2, yRadius: cursorWidth / 2).fill()
        }

        lastCursorRect = cursorRect
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        let margin: CGFloat = 40
        var expanded = rect
        expanded.origin.y -= margin
        expanded.size.height += margin * 2
        expanded.size.width += cursorWidth * 2
        super.setNeedsDisplay(expanded, avoidAdditionalLayout: flag)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCodeBlockBackgrounds(in: rect)
        drawInlineCodeBackgrounds(in: rect)
        drawSelectionHighlights(in: rect)
    }

    private func drawCodeBlockBackgrounds(in dirtyRect: NSRect) {
        guard let tracker = fencedCodeTracker,
              !tracker.fenceRanges.isEmpty,
              let tlm = textLayoutManager,
              let tcm = tlm.textContentManager else { return }

        // Use the viewport range to know which character offsets are accurately laid out.
        // Fragments outside this range have estimated positions that are wrong.
        guard let viewportRange = tlm.textViewportLayoutController.viewportRange else { return }
        let vpStart = tcm.offset(from: tcm.documentRange.location, to: viewportRange.location)
        let vpEnd = tcm.offset(from: tcm.documentRange.location, to: viewportRange.endLocation)
        guard vpStart != NSNotFound, vpEnd != NSNotFound else { return }

        let origin = textContainerOrigin
        let textMargin = TextMetrics.textMargin(for: Preferences.shared.font)
        let palette = Preferences.shared.themePalette(for: effectiveAppearance)
        let bgColor = palette.codeBlockFill

        for pair in tracker.fenceRanges {
            guard let close = pair.close else { continue }

            let startOffset = pair.open.location
            let endOffset = NSMaxRange(close)
            guard endOffset > startOffset else { continue }

            // Skip code blocks entirely outside the viewport
            guard startOffset < vpEnd && endOffset > vpStart else { continue }

            // Clamp lookups to the viewport — fragments outside have estimated (wrong) positions.
            let clampedStart = max(startOffset, vpStart)
            let clampedEnd = min(endOffset - 1, vpEnd - 1)
            guard clampedEnd >= clampedStart else { continue }

            let docStart = tcm.documentRange.location
            guard let startLoc = tcm.location(docStart, offsetBy: clampedStart),
                  let endLoc = tcm.location(docStart, offsetBy: clampedEnd) else { continue }

            guard let firstFrag = tlm.textLayoutFragment(for: startLoc),
                  let lastFrag = tlm.textLayoutFragment(for: endLoc) else { continue }

            var topY = firstFrag.layoutFragmentFrame.minY + origin.y
            var bottomY = lastFrag.layoutFragmentFrame.maxY + origin.y

            // If the code block extends beyond the viewport, stretch background to the
            // edges of the dirty rect so it looks continuous off-screen.
            let extendsAbove = startOffset < vpStart
            let extendsBelow = endOffset > vpEnd
            if extendsAbove { topY = dirtyRect.minY - 40 }
            if extendsBelow { bottomY = dirtyRect.maxY + 40 }

            guard bottomY > topY else { continue }

            let vPad: CGFloat = 4
            let containerWidth = textContainer?.size.width ?? bounds.width
            let blockRect = NSRect(
                x: origin.x + textMargin,
                y: topY - vPad,
                width: containerWidth - 2 * textMargin,
                height: (bottomY - topY) + 2 * vPad
            )

            guard blockRect.intersects(dirtyRect) else { continue }

            bgColor.setFill()
            // When edges extend off-screen, the rounded corners at those edges are
            // clipped anyway, so a uniform corner radius works fine.
            NSBezierPath(roundedRect: blockRect, xRadius: 10, yRadius: 10).fill()
        }
    }

    // MARK: - Inline code background

    private func drawInlineCodeBackgrounds(in dirtyRect: NSRect) {
        guard let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let ts = (tcm as? NSTextContentStorage)?.textStorage else { return }

        guard let viewportRange = tlm.textViewportLayoutController.viewportRange else { return }
        let docStart = tcm.documentRange.location
        let vpStart = tcm.offset(from: docStart, to: viewportRange.location)
        let vpEnd = tcm.offset(from: docStart, to: viewportRange.endLocation)
        guard vpStart != NSNotFound, vpEnd != NSNotFound, vpEnd > vpStart else { return }

        let str = ts.string as NSString
        let vpNSRange = NSRange(location: vpStart, length: min(vpEnd - vpStart, str.length - vpStart))

        let palette = Preferences.shared.themePalette(for: effectiveAppearance)
        let bgColor = palette.inlineCodeFill

        let origin = textContainerOrigin
        let vExpand: CGFloat = 2
        let hExpand: CGFloat = 3
        let cornerRadius: CGFloat = 4

        str.enumerateSubstrings(in: vpNSRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring else { return }

            // Skip lines inside fenced code blocks
            if let tracker = self.fencedCodeTracker,
               tracker.isInsideFencedCode(paragraphLocation: substringRange.location) {
                return
            }
            // Also skip fence lines themselves
            let trimmed = substring.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { return }

            let localRange = NSRange(location: 0, length: (substring as NSString).length)
            for match in MarkdownPatterns.inlineCode.matches(in: substring, range: localRange) {
                let matchRange = match.range
                let docRange = NSRange(location: substringRange.location + matchRange.location,
                                       length: matchRange.length)

                guard let startLoc = tcm.location(docStart, offsetBy: docRange.location),
                      let endLoc = tcm.location(docStart, offsetBy: NSMaxRange(docRange)),
                      let textRange = NSTextRange(location: startLoc, end: endLoc) else { continue }

                tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, segmentFrame, _, _ in
                    let rect = NSRect(
                        x: segmentFrame.minX + origin.x - hExpand,
                        y: segmentFrame.minY + origin.y - vExpand,
                        width: segmentFrame.width + 2 * hExpand,
                        height: segmentFrame.height + 2 * vExpand
                    )
                    if rect.intersects(dirtyRect) {
                        bgColor.setFill()
                        NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
                    }
                    return true
                }
            }
        }
    }

    private func drawSelectionHighlights(in dirtyRect: NSRect) {
        guard let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let viewportRange = tlm.textViewportLayoutController.viewportRange else { return }

        let viewportStart = tcm.offset(from: tcm.documentRange.location, to: viewportRange.location)
        let viewportEnd = tcm.offset(from: tcm.documentRange.location, to: viewportRange.endLocation)
        guard viewportStart != NSNotFound, viewportEnd != NSNotFound, viewportEnd >= viewportStart else { return }

        let viewportNSRange = NSRange(location: viewportStart, length: viewportEnd - viewportStart)
        let origin = textContainerOrigin

        for selectedValue in selectedRanges {
            let selectedRange = selectedValue.rangeValue
            guard selectedRange.length > 0,
                  let visibleRange = intersection(selectedRange, viewportNSRange),
                  let start = tcm.location(tcm.documentRange.location, offsetBy: visibleRange.location),
                  let end = tcm.location(start, offsetBy: visibleRange.length),
                  let textRange = NSTextRange(location: start, end: end) else {
                continue
            }

            var highlightRects: [NSRect] = []
            tlm.enumerateTextSegments(in: textRange, type: .selection, options: []) { _, segmentFrame, _, _ in
                guard segmentFrame.width > 0 else { return true }
                highlightRects.append(self.selectionRect(for: segmentFrame, origin: origin))
                return true
            }

            drawSelectionRects(highlightRects, in: dirtyRect)
        }
    }

    // MARK: - Auto-pair characters

    private let autoPairMap: [String: String] = [
        "(": ")",
        "[": "]",
        "\"": "\"",
    ]

    private let markdownWrapChars: Set<String> = ["*", "`", "~"]

    // MARK: - Input interception

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = string as? String, text.count == 1 else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let sel = selectedRange()

        // Markdown wrap characters: if selection exists, wrap it
        if markdownWrapChars.contains(text) && sel.length > 0 {
            guard let ts = textStorage else {
                super.insertText(string, replacementRange: replacementRange)
                return
            }
            let selected = (ts.string as NSString).substring(with: sel)
            let wrapped = "\(text)\(selected)\(text)"
            super.insertText(wrapped, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
            return
        }

        // Auto-pair brackets/quotes
        if let closing = autoPairMap[text] {
            if sel.length > 0 {
                // Wrap selection
                guard let ts = textStorage else {
                    super.insertText(string, replacementRange: replacementRange)
                    return
                }
                let selected = (ts.string as NSString).substring(with: sel)
                let wrapped = "\(text)\(selected)\(closing)"
                super.insertText(wrapped, replacementRange: sel)
                setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                return
            } else {
                // Insert pair, cursor between
                let pair = "\(text)\(closing)"
                super.insertText(pair, replacementRange: replacementRange)
                setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                return
            }
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: - Smart newline (list continuation)

    override func insertNewline(_ sender: Any?) {
        guard let (lineText, lineRange) = currentLineText() else {
            super.insertNewline(sender)
            return
        }

        if let continuation = listContinuation(for: lineText) {
            // Insert newline + continuation prefix
            let insertionPoint = NSMaxRange(selectedRange())
            super.insertText("\n\(continuation)", replacementRange: NSRange(location: insertionPoint, length: 0))
        } else if listPrefixRange(for: lineRange) != nil {
            // Line is just a list prefix with no content — clear it and insert plain newline
            let rangeToReplace = NSRange(location: lineRange.location, length: lineRange.length)
            super.insertText("\n", replacementRange: rangeToReplace)
        } else {
            super.insertNewline(sender)
        }
    }

    // MARK: - Indent / Outdent

    override func insertTab(_ sender: Any?) {
        indentSelectedLines(indent: true)
    }

    override func insertBacktab(_ sender: Any?) {
        indentSelectedLines(indent: false)
    }

    private func indentSelectedLines(indent: Bool) {
        guard let ts = textStorage else { return }
        let str = ts.string as NSString
        let sel = selectedRange()
        let linesRange = str.lineRange(for: sel)
        let linesText = str.substring(with: linesRange)
        let lines = linesText.components(separatedBy: "\n")

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            // Don't process the trailing empty string from split
            if i == lines.count - 1 && line.isEmpty {
                result.append(line)
                continue
            }
            if indent {
                result.append("    " + line)
            } else {
                if line.hasPrefix("    ") {
                    result.append(String(line.dropFirst(4)))
                } else if line.hasPrefix("\t") {
                    result.append(String(line.dropFirst(1)))
                } else {
                    // Remove leading spaces up to 4
                    var trimmed = line
                    var removed = 0
                    while removed < 4 && trimmed.hasPrefix(" ") {
                        trimmed = String(trimmed.dropFirst(1))
                        removed += 1
                    }
                    result.append(trimmed)
                }
            }
        }

        let newText = result.joined(separator: "\n")
        insertText(newText, replacementRange: linesRange)
        // Select the modified range
        setSelectedRange(NSRange(location: linesRange.location, length: (newText as NSString).length))
    }

    // MARK: - Typing attributes sync

    func syncTypingAttributes() {
        let prefs = Preferences.shared
        let element = currentParagraphElement()
        let font = EditorTypography.font(for: element, preferences: prefs)
        let style = EditorTypography.paragraphStyle(for: element, preferences: prefs)
        let palette = prefs.themePalette(for: effectiveAppearance)

        var attrs = typingAttributes
        attrs[.paragraphStyle] = style
        attrs[.font] = font
        attrs[.foregroundColor] = palette.editorText
        typingAttributes = attrs
    }

    func applyTheme(_ palette: EditorThemePalette) {
        selectionFillColor = palette.selectionFill
        selectedTextAttributes = [:]
        needsDisplay = true
    }

    // MARK: - Typewriter scroll

    override func didChangeText() {
        super.didChangeText()
        syncTypingAttributes()
        if Preferences.shared.isTypewriterScrollEnabled {
            centerSelectionIfNeeded(animated: false)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
        syncTypingAttributes()
        needsDisplay = true
        debugLogSelectionGeometryIfNeeded()
        if Preferences.shared.isTypewriterScrollEnabled {
            centerSelectionIfNeeded(animated: false)
        }

        // Notify for focus mode paragraph tracking
        NotificationCenter.default.post(
            name: NSNotification.Name("EditorSelectionDidChange"),
            object: self
        )
    }

    func centerSelectionIfNeeded(animated: Bool) {
        guard let scrollView = enclosingScrollView,
              let clipView = scrollView.contentView as NSClipView?,
              let tlm = textLayoutManager else {
            return
        }

        let selectedRange = selectedRange()
        let rect: NSRect
        if selectedRange.length == 0 {
            rect = insertionPointRect(for: selectedRange, using: tlm)
                ?? insertionPointFallbackRect(for: selectedRange, using: tlm)
                ?? .zero
        } else {
            rect = selectionRect(for: selectedRange, using: tlm)
                ?? insertionPointFallbackRect(for: selectedRange, using: tlm)
                ?? .zero
        }

        guard rect != .zero else { return }

        let insetRect = rect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
        let clipBounds = clipView.bounds
        let targetY = max(-scrollView.contentInsets.top, insetRect.midY - (clipBounds.height / 2.0))
        let maxY = max(-scrollView.contentInsets.top, bounds.height - clipBounds.height + scrollView.contentInsets.bottom)
        let constrainedY = min(max(targetY, -scrollView.contentInsets.top), maxY)
        let targetOrigin = NSPoint(x: clipBounds.origin.x, y: constrainedY)

        if animated {
            clipView.animator().setBoundsOrigin(targetOrigin)
        } else {
            clipView.setBoundsOrigin(targetOrigin)
        }

        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - TextKit 2 Cursor Geometry

    private func currentParagraphElement() -> MarkdownElement {
        guard let (lineText, lineRange) = currentLineText() else {
            return .plain
        }

        let isInFencedCode = fencedCodeTracker?.isInsideFencedCode(paragraphLocation: lineRange.location) ?? false
        return MarkdownPatterns.paragraphType(for: lineText, isInFencedCode: isInFencedCode)
    }

    private func resolvedInsertionPointRect(from rect: NSRect) -> NSRect {
        let baseRect: NSRect
        if let tlm = textLayoutManager {
            let selection = selectedRange()
            baseRect = insertionPointRect(for: selection, using: tlm)
                ?? insertionPointFallbackRect(for: selection, using: tlm)
                ?? rect
        } else {
            baseRect = rect
        }

        let rawHeight = baseRect.height > 0 ? baseRect.height : EditorTypography.fallbackCaretHeight(for: Preferences.shared.font)
        let drawHeight = max(2, floor(rawHeight))
        let drawY = baseRect.origin.y + ((rawHeight - drawHeight) / 2.0)

        return NSRect(
            x: baseRect.origin.x,
            y: drawY,
            width: cursorWidth,
            height: drawHeight
        ).integral
    }

    private func selectionRect(for nsRange: NSRange, using tlm: NSTextLayoutManager) -> NSRect? {
        guard let contentManager = tlm.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: nsRange.location),
              let end = contentManager.location(start, offsetBy: nsRange.length) else {
            return nil
        }

        guard let textRange = NSTextRange(location: start, end: end) else { return nil }
        var result: NSRect?
        let origin = textContainerOrigin

        tlm.enumerateTextSegments(in: textRange, type: .selection, options: []) { _, segmentFrame, _, _ in
            guard segmentFrame.width > 0 else { return true }

            let displayRect = self.selectionRect(for: segmentFrame, origin: origin)

            if let current = result {
                result = current.union(displayRect)
            } else {
                result = displayRect
            }
            return true
        }

        return result
    }

    private func insertionPointRect(for nsRange: NSRange, using tlm: NSTextLayoutManager) -> NSRect? {
        guard nsRange.length == 0,
              let contentManager = tlm.textContentManager,
              let location = contentManager.location(contentManager.documentRange.location, offsetBy: nsRange.location),
              let textRange = NSTextRange(location: location, end: location) else {
            return nil
        }

        var result: NSRect?
        tlm.enumerateTextSegments(
            in: textRange,
            type: .standard,
            options: [.rangeNotRequired, .upstreamAffinity]
        ) { _, segmentFrame, _, _ in
            result = self.caretRect(for: segmentFrame)
            return false
        }

        return result
    }

    private func insertionPointFallbackRect(for nsRange: NSRange, using tlm: NSTextLayoutManager) -> NSRect? {
        guard let contentManager = tlm.textContentManager else { return nil }

        guard let location = contentManager.location(contentManager.documentRange.location, offsetBy: nsRange.location) else {
            return nil
        }

        if let fragment = tlm.textLayoutFragment(for: location) {
            return fragment.layoutFragmentFrame
        }

        return nil
    }

    private func intersection(_ lhs: NSRange, _ rhs: NSRange) -> NSRange? {
        let start = max(lhs.location, rhs.location)
        let end = min(NSMaxRange(lhs), NSMaxRange(rhs))
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func selectionRect(for segmentFrame: NSRect, origin: NSPoint) -> NSRect {
        var rect = segmentFrame
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect.standardized
    }

    private func drawSelectionRects(_ rects: [NSRect], in dirtyRect: NSRect) {
        selectionFillColor.setFill()
        for rect in rects where rect.width > 0 && rect.height > 0 && rect.intersects(dirtyRect) {
            NSBezierPath(rect: rect).fill()
        }
    }

    private func caretRect(for segmentFrame: NSRect) -> NSRect {
        return NSRect(
            x: segmentFrame.minX,
            y: segmentFrame.minY,
            width: cursorWidth,
            height: max(2, segmentFrame.height)
        ).integral
    }

    private func fontForCaret(at location: Int) -> NSFont {
        fontAtCharacterOffset(max(0, location - (location > 0 ? 1 : 0)))
    }

    private func fontAtCharacterOffset(_ location: Int) -> NSFont {
        guard let textStorage, textStorage.length > 0 else {
            return Preferences.shared.font
        }

        let clamped = min(max(location, 0), textStorage.length - 1)
        return (textStorage.attribute(.font, at: clamped, effectiveRange: nil) as? NSFont) ?? Preferences.shared.font
    }

    private func paragraphStyleAtCharacterOffset(_ location: Int) -> NSParagraphStyle? {
        guard let textStorage, textStorage.length > 0 else {
            return nil
        }

        let clamped = min(max(location, 0), textStorage.length - 1)
        return textStorage.attribute(.paragraphStyle, at: clamped, effectiveRange: nil) as? NSParagraphStyle
    }

    private func documentOffset(for location: (any NSTextLocation)?) -> Int? {
        guard let location,
              let tlm = textLayoutManager,
              let tcm = tlm.textContentManager else {
            return nil
        }

        let offset = tcm.offset(from: tcm.documentRange.location, to: location)
        return offset == NSNotFound ? nil : offset
    }

    private func debugLogSelectionGeometryIfNeeded() {
        guard geometryLoggingEnabled,
              let tlm = textLayoutManager,
              let tcm = tlm.textContentManager else { return }

        let ranges = selectedRanges.map(\.rangeValue)
        NSLog("[Geometry] selection changed ranges=%@", String(describing: ranges))

        for selectedRange in ranges where selectedRange.length > 0 {
            guard let start = tcm.location(tcm.documentRange.location, offsetBy: selectedRange.location),
                  let end = tcm.location(start, offsetBy: selectedRange.length),
                  let textRange = NSTextRange(location: start, end: end) else {
                continue
            }

            tlm.enumerateTextSegments(in: textRange, type: .selection, options: []) { (segmentRange: NSTextRange?, segmentFrame: CGRect, _: CGFloat, _: NSTextContainer) -> Bool in
                guard segmentFrame.width > 0 else { return true }

                let offset = self.documentOffset(for: segmentRange?.location) ?? selectedRange.location
                let font = self.fontAtCharacterOffset(offset)
                let paragraphStyle = self.paragraphStyleAtCharacterOffset(offset)
                let drawnRect = self.selectionRect(for: segmentFrame, origin: self.textContainerOrigin)
                let fragmentDebug = self.lineFragmentDebugDescription(at: offset)
                let rangeDescription: String
                if let segmentRange,
                   let endOffset = self.documentOffset(for: segmentRange.endLocation) {
                    rangeDescription = "{\(offset),\(max(0, endOffset - offset))}"
                } else {
                    rangeDescription = "{\(offset),?}"
                }

                NSLog("""
                [Geometry][Selection]
                  range=\(rangeDescription)
                  font=\(font.fontName) size=\(String(format: "%.2f", font.pointSize))
                  asc=\(String(format: "%.2f", font.ascender)) desc=\(String(format: "%.2f", font.descender)) leading=\(String(format: "%.2f", font.leading))
                  fixedLineHeight=\(String(format: "%.2f", EditorTypography.fixedLineHeight(for: font))) lineHeightMultiple=\(String(format: "%.2f", EditorTypography.normalizedLineHeightMultiple(for: paragraphStyle)))
                  segmentFrame=\(NSStringFromRect(segmentFrame))
                  drawnSelectionRect=\(NSStringFromRect(drawnRect))
                  \(fragmentDebug)
                """)
                return true
            }
        }
    }

    private func debugLogInsertionGeometryIfNeeded(sourceRect: NSRect, resolvedRect: NSRect) {
        guard geometryLoggingEnabled,
              resolvedRect != lastLoggedCursorRect,
              let tlm = textLayoutManager,
              let selectedRange = selectedRanges.first?.rangeValue,
              selectedRange.length == 0,
              let insertionRect = insertionPointRect(for: selectedRange, using: tlm) else {
            return
        }

        let font = fontForCaret(at: selectedRange.location)
        let paragraphStyle = paragraphStyleAtCharacterOffset(selectedRange.location)
        let fragmentDebug = lineFragmentDebugDescription(at: selectedRange.location)

        NSLog("""
        [Geometry][Caret]
          location=\(selectedRange.location)
          font=\(font.fontName) size=\(String(format: "%.2f", font.pointSize))
          asc=\(String(format: "%.2f", font.ascender)) desc=\(String(format: "%.2f", font.descender)) leading=\(String(format: "%.2f", font.leading))
          fixedLineHeight=\(String(format: "%.2f", EditorTypography.fixedLineHeight(for: font))) lineHeightMultiple=\(String(format: "%.2f", EditorTypography.normalizedLineHeightMultiple(for: paragraphStyle)))
          sourceRect=\(NSStringFromRect(sourceRect))
          insertionRect=\(NSStringFromRect(insertionRect))
          resolvedCursorRect=\(NSStringFromRect(resolvedRect))
          \(fragmentDebug)
        """)

        lastLoggedCursorRect = resolvedRect
    }

    private func lineFragmentDebugDescription(at location: Int) -> String {
        guard let tlm = textLayoutManager,
              let tcm = tlm.textContentManager,
              let textLocation = tcm.location(tcm.documentRange.location, offsetBy: location),
              let layoutFragment = tlm.textLayoutFragment(for: textLocation),
              let lineFragment = layoutFragment.textLineFragment(for: textLocation, isUpstreamAffinity: location > 0) else {
            return "layoutFragment=nil"
        }

        return """
        layoutFragmentFrame=\(NSStringFromRect(layoutFragment.layoutFragmentFrame))
        renderingSurfaceBounds=\(NSStringFromRect(layoutFragment.renderingSurfaceBounds))
        lineTypographicBounds=\(NSStringFromRect(lineFragment.typographicBounds))
        glyphOrigin=\(NSStringFromPoint(lineFragment.glyphOrigin))
        """
    }

}
