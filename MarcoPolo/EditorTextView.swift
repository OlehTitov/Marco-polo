import AppKit

final class EditorTextView: NSTextView {

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
            if let prefixRange = listPrefixRange(for: lineRange) {
                // Replace the prefix line with just a newline
                let rangeToReplace = NSRange(location: lineRange.location, length: lineRange.length)
                super.insertText("\n", replacementRange: rangeToReplace)
            }
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

    // MARK: - Typewriter scroll

    override func didChangeText() {
        super.didChangeText()
        if Preferences.shared.isTypewriterScrollEnabled {
            centerSelectionIfNeeded(animated: false)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
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
