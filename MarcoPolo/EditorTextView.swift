import AppKit

final class EditorTextView: NSTextView {

    var fencedCodeTracker: FencedCodeTracker?

    // MARK: - Insertion point

    private let cursorWidth: CGFloat = 4
    private var lastCursorRect: NSRect = .zero

    private var cursorHeight: CGFloat {
        let font = Preferences.shared.font
        return ceil(font.pointSize * 1.8)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let h = cursorHeight
        let midY = rect.origin.y + rect.height / 2
        let cursorRect = NSRect(
            x: rect.origin.x,
            y: midY - h / 2,
            width: cursorWidth,
            height: h
        )

        if lastCursorRect != .zero {
            setNeedsDisplay(lastCursorRect, avoidAdditionalLayout: true)
        }

        if flag {
            insertionPointColor.setFill()
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

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark ? NSColor.white.withAlphaComponent(0.03)
                             : NSColor.black.withAlphaComponent(0.03)

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

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor = isDark ? NSColor.white.withAlphaComponent(0.08)
                             : NSColor.black.withAlphaComponent(0.06)

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
        let margin = TextMetrics.textMargin(for: Preferences.shared.font)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 12
        style.headIndent = margin
        style.firstLineHeadIndent = margin

        var attrs = typingAttributes
        attrs[.paragraphStyle] = style
        attrs[.font] = Preferences.shared.font
        typingAttributes = attrs
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
        let rect = cursorRect(for: selectedRange, using: tlm)
            ?? insertionPointFallbackRect(for: selectedRange, using: tlm)
            ?? .zero

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

    private func cursorRect(for nsRange: NSRange, using tlm: NSTextLayoutManager) -> NSRect? {
        guard let contentManager = tlm.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: nsRange.location),
              let end = contentManager.location(start, offsetBy: max(nsRange.length, 1)) else {
            return nil
        }

        guard let textRange = NSTextRange(location: start, end: end) else { return nil }
        var result: NSRect?

        tlm.enumerateTextSegments(in: textRange, type: .selection, options: []) { _, segmentFrame, _, _ in
            if let current = result {
                result = current.union(segmentFrame)
            } else {
                result = segmentFrame
            }
            return true
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

}
