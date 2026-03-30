import AppKit
import QuartzCore

private final class EditorCaretOverlayView: NSView {
    var caretRect: NSRect = .zero {
        didSet {
            if oldValue != .zero {
                needsDisplay = true
            }
            if caretRect != .zero {
                needsDisplay = true
            }
        }
    }

    var caretColor: NSColor = .systemBlue {
        didSet {
            if caretColor != oldValue {
                needsDisplay = true
            }
        }
    }

    var caretAlpha: CGFloat = 0.78 {
        didSet {
            if caretAlpha != oldValue {
                needsDisplay = true
            }
        }
    }

    var isCaretVisible = false {
        didSet {
            if isCaretVisible != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        alphaValue = 0
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard isCaretVisible,
              caretRect.width > 0,
              caretRect.height > 0,
              caretRect.intersects(dirtyRect) else {
            return
        }

        caretColor.withAlphaComponent(caretAlpha).setFill()
        NSBezierPath(
            roundedRect: caretRect,
            xRadius: caretRect.width / 2.0,
            yRadius: caretRect.width / 2.0
        ).fill()
    }

    func showImmediately() {
        layer?.removeAllAnimations()
        isCaretVisible = true
        alphaValue = 1
    }

    func hideImmediately() {
        layer?.removeAllAnimations()
        isCaretVisible = false
        alphaValue = 0
    }

    func fadeOut(duration: TimeInterval) {
        guard isCaretVisible else { return }

        layer?.removeAllAnimations()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.isCaretVisible = false
            self?.alphaValue = 0
        }
    }
}

final class EditorTextView: NSTextView {

    var fencedCodeTracker: FencedCodeTracker?
    private var selectionFillColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.26)
    private let geometryLoggingEnabled = true
    private var lastLoggedCursorRect: NSRect = .zero
    private let caretOverlayView = EditorCaretOverlayView(frame: .zero)
    private weak var observedWindow: NSWindow?
    private var windowKeyObservers: [NSObjectProtocol] = []
    private var caretBlinkTimer: Timer?
    private var isCaretBlinkOn = true
    private var caretColor = NSColor.systemBlue
    private var capturedAppKitInsertionPointRect: NSRect?
    private var capturedAppKitInsertionPointLocation: Int?
    private var isCaretOverlayUpdateScheduledFromAppKitRect = false
    private var pointerGestureSequence = 0
    private var activePointerGestureSequence: Int?
    private var activePointerGestureStartedNearCaret = false
    private var caretDragStartPoint: NSPoint?
    private var caretDragAnchorRange: NSRange?
    private var caretDragAnchorSelections: [NSTextSelection] = []
    private var caretDragAnchorLocation: NSTextLocation?
    private var isHandlingCustomCaretSelectionDrag = false

    // MARK: - Insertion point

    private let cursorWidth: CGFloat = 3
    private let cursorHeightScale: CGFloat = 1.4
    private let cursorAlpha: CGFloat = 0.78
    private let cursorBlinkInterval: TimeInterval = 0.68
    private let cursorFadeDuration: TimeInterval = 0.20
    private let caretPointerHitSlop: CGFloat = 6
    private let caretDragActivationDistance: CGFloat = 2

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        tearDownCaretInfrastructure()
    }

    private func commonInit() {
        caretOverlayView.caretColor = caretColor
        caretOverlayView.caretAlpha = cursorAlpha
        super.insertionPointColor = .clear
    }

    func setCaretColor(_ color: NSColor) {
        caretColor = color
        caretOverlayView.caretColor = color
        super.insertionPointColor = .clear
        updateCaretOverlay(resetBlink: false)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        captureAppKitInsertionPointRect(rect)
        // Intentionally avoid calling super. Marco Polo renders its own caret
        // overlay, but it now anchors that overlay to AppKit's insertion rect.
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if observedWindow !== window {
            removeWindowKeyObservers()
            observedWindow = window
        }
        invalidateCapturedAppKitInsertionPointRect()
        installCaretInfrastructureIfNeeded()
        updateCaretOverlay(resetBlink: true)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        invalidateCapturedAppKitInsertionPointRect()
        installCaretInfrastructureIfNeeded()
        updateCaretOverlay(resetBlink: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateCapturedAppKitInsertionPointRect()
        updateCaretOverlay(resetBlink: false)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        pointerGestureSequence += 1
        activePointerGestureSequence = pointerGestureSequence
        activePointerGestureStartedNearCaret = shouldTrackPointerGesture(at: localPoint)
        prepareCaretDragStateIfNeeded(at: localPoint)
        debugLogPointerEventIfNeeded("mouseDown.before", event: event, localPoint: localPoint)
        super.mouseDown(with: event)
        debugLogPointerEventIfNeeded("mouseDown.after", event: event, localPoint: localPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        debugLogPointerEventIfNeeded("mouseDragged.before", event: event, localPoint: localPoint)

        if handleCustomCaretSelectionDragIfNeeded(at: localPoint) {
            debugLogPointerEventIfNeeded("mouseDragged.custom", event: event, localPoint: localPoint)
            return
        }

        super.mouseDragged(with: event)

        _ = handleCustomCaretSelectionDragIfNeeded(at: localPoint)
        debugLogPointerEventIfNeeded("mouseDragged.after", event: event, localPoint: localPoint)
    }

    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        debugLogPointerEventIfNeeded("mouseUp.before", event: event, localPoint: localPoint)

        if isHandlingCustomCaretSelectionDrag {
            debugLogCustomCaretDragIfNeeded("mouseUp.custom", localPoint: localPoint, selections: nil)
        } else {
            super.mouseUp(with: event)
        }

        debugLogPointerEventIfNeeded("mouseUp.after", event: event, localPoint: localPoint)
        resetCaretDragState()
        activePointerGestureSequence = nil
        activePointerGestureStartedNearCaret = false
    }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome {
            updateCaretOverlay(resetBlink: true)
        }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            updateCaretOverlay(resetBlink: false)
        }
        return didResign
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
        invalidateCapturedAppKitInsertionPointRect()
        syncTypingAttributes()
        updateCaretOverlay(resetBlink: true)
        if Preferences.shared.isTypewriterScrollEnabled {
            centerSelectionIfNeeded(animated: false)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
        invalidateCapturedAppKitInsertionPointRectIfNeeded(for: ranges)
        syncTypingAttributes()
        needsDisplay = true
        debugLogSelectionChangeDuringPointerGestureIfNeeded(
            ranges: ranges,
            affinity: affinity,
            stillSelecting: flag
        )
        debugLogSelectionGeometryIfNeeded()
        debugLogCaretSnapshotIfNeeded()
        updateCaretOverlay(resetBlink: true)
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

    private func resolvedInsertionPointRect(
        from rect: NSRect,
        fallbackRect baseRect: NSRect? = nil,
        alignToSourceMidX: Bool = false
    ) -> NSRect {
        let sourceRect = baseRect ?? rect
        let caretFont = fontForCaret(at: selectedRange().location)
        let rawHeight = sourceRect.height > 0 ? sourceRect.height : EditorTypography.fallbackCaretHeight(for: caretFont)
        let targetHeight = max(2, round(caretFont.pointSize * cursorHeightScale))
        let drawHeight = min(rawHeight, targetHeight)
        let drawY = sourceRect.origin.y + ((rawHeight - drawHeight) / 2.0)
        let anchorX = alignToSourceMidX ? sourceRect.midX : sourceRect.minX
        let drawX = anchorX - (cursorWidth / 2.0)

        return NSRect(
            x: drawX,
            y: drawY,
            width: cursorWidth,
            height: drawHeight
        ).standardized
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

    private func debugLogCaretSnapshotIfNeeded() {
        guard geometryLoggingEnabled,
              let tlm = textLayoutManager,
              let selectedRange = selectedRanges.first?.rangeValue,
              selectedRange.length == 0 else {
            return
        }

        let sourceRect = rawInsertionPointDisplayRect(for: selectedRange, using: tlm)
            ?? .zero
        guard sourceRect != .zero else { return }

        let resolvedRect = resolvedInsertionPointDisplayRect(for: selectedRange, using: tlm)
            ?? resolvedInsertionPointRect(
                from: sourceRect,
                fallbackRect: sourceRect,
                alignToSourceMidX: appKitInsertionPointDisplayRect(for: selectedRange) != nil
            )
        debugLogInsertionGeometryIfNeeded(sourceRect: sourceRect, resolvedRect: resolvedRect)
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
            result = segmentFrame.standardized
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

    private func resolvedInsertionPointDisplayRect(for nsRange: NSRange, using tlm: NSTextLayoutManager) -> NSRect? {
        if let appKitRect = appKitInsertionPointDisplayRect(for: nsRange) {
            return resolvedInsertionPointRect(
                from: appKitRect,
                fallbackRect: appKitRect,
                alignToSourceMidX: true
            )
        }

        let baseRect = insertionPointRect(for: nsRange, using: tlm)
            ?? insertionPointFallbackRect(for: nsRange, using: tlm)
        guard let baseRect else { return nil }
        let resolved = resolvedInsertionPointRect(from: baseRect, fallbackRect: baseRect)
        return displayRect(forTextContainerRect: resolved)
    }

    private func rawInsertionPointDisplayRect(for nsRange: NSRange, using tlm: NSTextLayoutManager) -> NSRect? {
        if let appKitRect = appKitInsertionPointDisplayRect(for: nsRange) {
            return appKitRect
        }

        let baseRect = insertionPointRect(for: nsRange, using: tlm)
            ?? insertionPointFallbackRect(for: nsRange, using: tlm)
        guard let baseRect else { return nil }
        return displayRect(forTextContainerRect: baseRect)
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

    private func displayRect(forTextContainerRect rect: NSRect) -> NSRect {
        var displayRect = rect
        let origin = textContainerOrigin
        displayRect.origin.x += origin.x
        displayRect.origin.y += origin.y
        return displayRect.standardized
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
              selectedRange.length == 0 else {
            return
        }

        let insertionRect = insertionPointRect(for: selectedRange, using: tlm)
        let fallbackRect = insertionPointFallbackRect(for: selectedRange, using: tlm)
        let appKitRect = appKitInsertionPointDisplayRect(for: selectedRange)
        guard insertionRect != nil || fallbackRect != nil || sourceRect != .zero else { return }

        let font = fontForCaret(at: selectedRange.location)
        let paragraphStyle = paragraphStyleAtCharacterOffset(selectedRange.location)
        let fragmentDebug = lineFragmentDebugDescription(at: selectedRange.location)
        let rawHeight = (insertionRect ?? fallbackRect ?? sourceRect).height
        let targetHeight = max(2, round(font.pointSize * cursorHeightScale))
        let drawHeight = resolvedRect.height

        NSLog("""
        [Geometry][Caret]
          location=\(selectedRange.location)
          font=\(font.fontName) size=\(String(format: "%.2f", font.pointSize))
          asc=\(String(format: "%.2f", font.ascender)) desc=\(String(format: "%.2f", font.descender)) leading=\(String(format: "%.2f", font.leading))
          fixedLineHeight=\(String(format: "%.2f", EditorTypography.fixedLineHeight(for: font))) lineHeightMultiple=\(String(format: "%.2f", EditorTypography.normalizedLineHeightMultiple(for: paragraphStyle)))
          cursorWidth=\(String(format: "%.2f", cursorWidth)) cursorHeightScale=\(String(format: "%.2f", cursorHeightScale))
          rawCaretHeight=\(String(format: "%.2f", rawHeight)) targetCaretHeight=\(String(format: "%.2f", targetHeight)) drawCaretHeight=\(String(format: "%.2f", drawHeight))
          sourceRect=\(NSStringFromRect(sourceRect))
          appKitInsertionRect=\(appKitRect.map(NSStringFromRect) ?? "nil")
          insertionRect=\(insertionRect.map(NSStringFromRect) ?? "nil")
          fallbackRect=\(fallbackRect.map(NSStringFromRect) ?? "nil")
          resolvedCursorRect=\(NSStringFromRect(resolvedRect))
          \(fragmentDebug)
        """)

        lastLoggedCursorRect = resolvedRect
    }

    // MARK: - Custom caret overlay

    private var shouldShowCustomCaret: Bool {
        guard selectedRange().length == 0,
              isEditable,
              window?.isKeyWindow == true,
              window?.firstResponder === self else {
            return false
        }
        return true
    }

    private func installCaretInfrastructureIfNeeded() {
        installCaretOverlayIfNeeded()
        installWindowKeyObservers()
    }

    private func installCaretOverlayIfNeeded() {
        guard let hostView = superview else { return }
        if caretOverlayView.superview !== hostView {
            caretOverlayView.removeFromSuperview()
            caretOverlayView.frame = frame
            hostView.addSubview(caretOverlayView, positioned: .below, relativeTo: self)
        }
    }

    private func installWindowKeyObservers() {
        guard windowKeyObservers.isEmpty, let window else { return }

        let notificationCenter = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]

        windowKeyObservers = names.map { name in
            notificationCenter.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updateCaretOverlay(resetBlink: false)
            }
        }
    }

    private func tearDownCaretInfrastructure() {
        removeWindowKeyObservers()
        stopCaretBlinkTimer()
        caretOverlayView.removeFromSuperview()
    }

    private func removeWindowKeyObservers() {
        if !windowKeyObservers.isEmpty {
            let notificationCenter = NotificationCenter.default
            windowKeyObservers.forEach(notificationCenter.removeObserver)
            windowKeyObservers.removeAll()
        }
        observedWindow = nil
    }

    private func updateCaretOverlay(resetBlink: Bool) {
        installCaretInfrastructureIfNeeded()
        guard let tlm = textLayoutManager,
              let hostView = caretOverlayView.superview else {
            caretOverlayView.hideImmediately()
            caretOverlayView.caretRect = .zero
            stopCaretBlinkTimer()
            return
        }

        caretOverlayView.caretColor = caretColor
        caretOverlayView.frame = hostView === self ? bounds : frame

        guard shouldShowCustomCaret,
              let selectedRange = selectedRanges.first?.rangeValue,
              let displayRect = resolvedInsertionPointDisplayRect(for: selectedRange, using: tlm) else {
            caretOverlayView.hideImmediately()
            caretOverlayView.caretRect = .zero
            stopCaretBlinkTimer()
            return
        }

        let overlayRect = convert(displayRect, to: caretOverlayView).standardized
        caretOverlayView.caretRect = overlayRect

        if resetBlink {
            restartCaretBlink()
        } else {
            updateCaretBlinkTimerIfNeeded()
            if isCaretBlinkOn {
                caretOverlayView.showImmediately()
            } else if !caretOverlayView.isCaretVisible {
                caretOverlayView.hideImmediately()
            }
        }
    }

    private func restartCaretBlink() {
        isCaretBlinkOn = true
        caretOverlayView.showImmediately()
        updateCaretBlinkTimerIfNeeded(restart: true)
    }

    private func updateCaretBlinkTimerIfNeeded(restart: Bool = false) {
        guard shouldShowCustomCaret else {
            stopCaretBlinkTimer()
            return
        }

        if restart {
            stopCaretBlinkTimer()
        }

        guard caretBlinkTimer == nil else { return }

        let timer = Timer(timeInterval: cursorBlinkInterval, repeats: true) { [weak self] _ in
            self?.toggleCaretBlink()
        }
        caretBlinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopCaretBlinkTimer() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        isCaretBlinkOn = true
    }

    private func toggleCaretBlink() {
        guard shouldShowCustomCaret else {
            updateCaretOverlay(resetBlink: false)
            return
        }

        isCaretBlinkOn.toggle()
        if isCaretBlinkOn {
            caretOverlayView.showImmediately()
        } else {
            caretOverlayView.fadeOut(duration: cursorFadeDuration)
        }
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

    private func captureAppKitInsertionPointRect(_ rect: NSRect) {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0 else { return }

        let standardizedRect = rect.standardized
        let location = selectedRange.location
        let didChange =
            capturedAppKitInsertionPointRect != standardizedRect ||
            capturedAppKitInsertionPointLocation != location

        capturedAppKitInsertionPointRect = standardizedRect
        capturedAppKitInsertionPointLocation = location

        guard didChange else { return }
        scheduleCaretOverlayUpdateFromCapturedAppKitRect()
    }

    private func appKitInsertionPointDisplayRect(for nsRange: NSRange) -> NSRect? {
        guard nsRange.length == 0,
              capturedAppKitInsertionPointLocation == nsRange.location,
              let rect = capturedAppKitInsertionPointRect,
              rect != .zero else {
            return nil
        }

        return rect
    }

    private func invalidateCapturedAppKitInsertionPointRect() {
        capturedAppKitInsertionPointRect = nil
        capturedAppKitInsertionPointLocation = nil
    }

    private func invalidateCapturedAppKitInsertionPointRectIfNeeded(for ranges: [NSValue]) {
        guard ranges.count == 1,
              let selectedRange = ranges.first?.rangeValue,
              selectedRange.length == 0,
              capturedAppKitInsertionPointLocation == selectedRange.location else {
            invalidateCapturedAppKitInsertionPointRect()
            return
        }
    }

    private func scheduleCaretOverlayUpdateFromCapturedAppKitRect() {
        guard !isCaretOverlayUpdateScheduledFromAppKitRect else { return }
        isCaretOverlayUpdateScheduledFromAppKitRect = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isCaretOverlayUpdateScheduledFromAppKitRect = false
            self.updateCaretOverlay(resetBlink: false)
        }
    }

    private func prepareCaretDragStateIfNeeded(at localPoint: NSPoint) {
        resetCaretDragState()

        guard activePointerGestureStartedNearCaret,
              let tlm = textLayoutManager,
              let tcm = tlm.textContentManager else {
            return
        }

        let anchorRange = selectedRange()
        guard anchorRange.length == 0,
              let anchorLocation = tcm.location(tcm.documentRange.location, offsetBy: anchorRange.location) else {
            return
        }

        caretDragStartPoint = localPoint
        caretDragAnchorRange = anchorRange
        caretDragAnchorLocation = anchorLocation

        let point = pointInTextContainerCoordinates(localPoint)
        let bounds = interactionBoundsInTextContainerCoordinates()
        let anchorSelections = tlm.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: anchorLocation,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: bounds
        )

        if anchorSelections.isEmpty {
            caretDragAnchorSelections = [NSTextSelection(anchorLocation, affinity: .downstream)]
        } else {
            caretDragAnchorSelections = anchorSelections
        }

        debugLogCustomCaretDragIfNeeded("mouseDown.anchor", localPoint: localPoint, selections: caretDragAnchorSelections)
    }

    private func handleCustomCaretSelectionDragIfNeeded(at localPoint: NSPoint) -> Bool {
        guard activePointerGestureStartedNearCaret,
              let tlm = textLayoutManager,
              let anchorRange = caretDragAnchorRange,
              let anchorLocation = caretDragAnchorLocation,
              let dragStartPoint = caretDragStartPoint,
              !caretDragAnchorSelections.isEmpty else {
            return false
        }

        let currentSelection = selectedRange()
        if !isHandlingCustomCaretSelectionDrag {
            let distance = hypot(localPoint.x - dragStartPoint.x, localPoint.y - dragStartPoint.y)
            guard distance >= caretDragActivationDistance else { return false }

            // If AppKit already started a native drag-selection, stay out of the way.
            guard currentSelection == anchorRange else { return false }
            isHandlingCustomCaretSelectionDrag = true
        }

        let point = pointInTextContainerCoordinates(localPoint)
        let bounds = interactionBoundsInTextContainerCoordinates()
        let selections = tlm.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: anchorLocation,
            anchors: caretDragAnchorSelections,
            modifiers: .extend,
            selecting: true,
            bounds: bounds
        )

        guard let rangeValues = nsValueRanges(from: selections), !rangeValues.isEmpty else {
            return false
        }

        let affinity = selectionAffinity(for: selections.first)
        debugLogCustomCaretDragIfNeeded("mouseDragged.apply", localPoint: localPoint, selections: selections)
        setSelectedRanges(rangeValues, affinity: affinity, stillSelecting: true)
        return true
    }

    private func resetCaretDragState() {
        caretDragStartPoint = nil
        caretDragAnchorRange = nil
        caretDragAnchorSelections = []
        caretDragAnchorLocation = nil
        isHandlingCustomCaretSelectionDrag = false
    }

    private func pointInTextContainerCoordinates(_ point: NSPoint) -> NSPoint {
        let origin = textContainerOrigin
        return NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    private func interactionBoundsInTextContainerCoordinates() -> NSRect {
        visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y).standardized
    }

    private func nsValueRanges(from selections: [NSTextSelection]) -> [NSValue]? {
        guard let tlm = textLayoutManager,
              let tcm = tlm.textContentManager else {
            return nil
        }

        let documentLocation = tcm.documentRange.location
        let ranges = selections.flatMap { selection in
            selection.textRanges.compactMap { textRange -> NSValue? in
                let start = tcm.offset(from: documentLocation, to: textRange.location)
                let end = tcm.offset(from: documentLocation, to: textRange.endLocation)
                guard start != NSNotFound, end != NSNotFound else { return nil }
                let lowerBound = min(start, end)
                let upperBound = max(start, end)
                return NSValue(range: NSRange(location: lowerBound, length: upperBound - lowerBound))
            }
        }

        return ranges.isEmpty ? nil : ranges
    }

    private func selectionAffinity(for selection: NSTextSelection?) -> NSSelectionAffinity {
        guard let selection else { return .downstream }
        switch selection.affinity {
        case .upstream:
            return .upstream
        case .downstream:
            return .downstream
        @unknown default:
            return .downstream
        }
    }

    private func overlayCaretRectInTextViewCoordinates() -> NSRect? {
        guard caretOverlayView.superview != nil,
              caretOverlayView.caretRect != .zero else {
            return nil
        }

        return convert(caretOverlayView.caretRect, from: caretOverlayView).standardized
    }

    private func expandedCaretHitRect(_ rect: NSRect?) -> NSRect? {
        guard let rect, rect != .zero else { return nil }
        return rect.insetBy(dx: -caretPointerHitSlop, dy: -caretPointerHitSlop).standardized
    }

    private func shouldTrackPointerGesture(at localPoint: NSPoint) -> Bool {
        let selectedRange = selectedRange()
        guard selectedRange.length == 0 else { return false }

        let appKitRect = appKitInsertionPointDisplayRect(for: selectedRange)
        let overlayRect = overlayCaretRectInTextViewCoordinates()
        let rawRect: NSRect?
        if let tlm = textLayoutManager {
            rawRect = rawInsertionPointDisplayRect(for: selectedRange, using: tlm)
        } else {
            rawRect = nil
        }

        let hitRects = [appKitRect, overlayRect, rawRect].compactMap(expandedCaretHitRect)
        return hitRects.contains { $0.contains(localPoint) }
    }

    private func debugLogPointerEventIfNeeded(_ phase: String, event: NSEvent, localPoint: NSPoint) {
        guard geometryLoggingEnabled else { return }

        if phase.hasPrefix("mouseDown") || activePointerGestureStartedNearCaret {
            let selectedRange = selectedRange()
            let appKitRect = appKitInsertionPointDisplayRect(for: selectedRange)
            let overlayRect = overlayCaretRectInTextViewCoordinates()
            let rawRect: NSRect?
            if let tlm = textLayoutManager {
                rawRect = rawInsertionPointDisplayRect(for: selectedRange, using: tlm)
            } else {
                rawRect = nil
            }

            let appKitHitRect = expandedCaretHitRect(appKitRect)
            let overlayHitRect = expandedCaretHitRect(overlayRect)
            let rawHitRect = expandedCaretHitRect(rawRect)
            let gestureID = activePointerGestureSequence ?? pointerGestureSequence

            NSLog("""
            [CaretDrag][Pointer]
              gesture=\(gestureID) phase=\(phase) startedNearCaret=\(activePointerGestureStartedNearCaret)
              type=\(event.type.rawValue) clickCount=\(event.clickCount) pressedMouseButtons=\(NSEvent.pressedMouseButtons)
              point=\(NSStringFromPoint(localPoint)) delta={\(String(format: "%.2f", event.deltaX)), \(String(format: "%.2f", event.deltaY))}
              selectedRange=\(NSStringFromRange(selectedRange))
              appKitRect=\(appKitRect.map(NSStringFromRect) ?? "nil") hitRect=\(appKitHitRect.map(NSStringFromRect) ?? "nil") contains=\(appKitHitRect?.contains(localPoint) ?? false)
              overlayRect=\(overlayRect.map(NSStringFromRect) ?? "nil") hitRect=\(overlayHitRect.map(NSStringFromRect) ?? "nil") contains=\(overlayHitRect?.contains(localPoint) ?? false)
              rawRect=\(rawRect.map(NSStringFromRect) ?? "nil") hitRect=\(rawHitRect.map(NSStringFromRect) ?? "nil") contains=\(rawHitRect?.contains(localPoint) ?? false)
            """)
        }
    }

    private func debugLogSelectionChangeDuringPointerGestureIfNeeded(
        ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        guard geometryLoggingEnabled,
              activePointerGestureSequence != nil || activePointerGestureStartedNearCaret else {
            return
        }

        let rangeDescriptions = ranges.map { NSStringFromRange($0.rangeValue) }.joined(separator: ", ")
        NSLog("""
        [CaretDrag][SelectionChange]
          gesture=\(activePointerGestureSequence ?? pointerGestureSequence) startedNearCaret=\(activePointerGestureStartedNearCaret)
          stillSelecting=\(stillSelecting) affinity=\(affinity.rawValue)
          ranges=[\(rangeDescriptions)]
        """)
    }

    private func debugLogCustomCaretDragIfNeeded(_ phase: String, localPoint: NSPoint, selections: [NSTextSelection]?) {
        guard geometryLoggingEnabled else { return }

        let selectionDescriptions = selections?.map { selection -> String in
            let ranges = selection.textRanges.compactMap { textRange -> String? in
                guard let start = documentOffset(for: textRange.location),
                      let end = documentOffset(for: textRange.endLocation) else {
                    return nil
                }
                let lowerBound = min(start, end)
                let upperBound = max(start, end)
                return NSStringFromRange(NSRange(location: lowerBound, length: upperBound - lowerBound))
            }.joined(separator: ", ")
            return "{affinity=\(selection.affinity.rawValue) granularity=\(selection.granularity.rawValue) ranges=[\(ranges)] anchorOffset=\(String(format: "%.2f", selection.anchorPositionOffset))}"
        }.joined(separator: " ") ?? "nil"

        NSLog("""
        [CaretDrag][Custom]
          gesture=\(activePointerGestureSequence ?? pointerGestureSequence) phase=\(phase) active=\(isHandlingCustomCaretSelectionDrag)
          localPoint=\(NSStringFromPoint(localPoint)) anchorRange=\(caretDragAnchorRange.map(NSStringFromRange) ?? "nil")
          selections=\(selectionDescriptions)
        """)
    }

}
