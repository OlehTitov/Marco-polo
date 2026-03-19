import AppKit

// MARK: - Formatting toggle commands (extension on EditorTextView)

extension EditorTextView {

    @objc func toggleBold(_ sender: Any?) {
        toggleWrap(marker: "**")
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggleWrap(marker: "*")
    }

    @objc func toggleInlineCode(_ sender: Any?) {
        toggleWrap(marker: "`")
    }

    @objc func insertMarkdownLink(_ sender: Any?) {
        let sel = selectedRange()
        guard let ts = textStorage else { return }

        if sel.length > 0 {
            let selectedText = (ts.string as NSString).substring(with: sel)
            let replacement = "[\(selectedText)](url)"
            insertText(replacement, replacementRange: sel)
            // Select "url" placeholder
            let urlStart = sel.location + selectedText.count + 3
            setSelectedRange(NSRange(location: urlStart, length: 3))
        } else {
            let linkTemplate = "[text](url)"
            insertText(linkTemplate, replacementRange: sel)
            // Select "text" placeholder
            let textStart = sel.location + 1
            setSelectedRange(NSRange(location: textStart, length: 4))
        }
    }

    // MARK: - Toggle wrap helper

    private func toggleWrap(marker: String) {
        let sel = selectedRange()
        guard let ts = textStorage else { return }
        let str = ts.string as NSString
        let markerLen = marker.count

        if sel.length > 0 {
            let selectedText = str.substring(with: sel)
            // Check if already wrapped
            let beforeStart = sel.location - markerLen
            let afterEnd = sel.location + sel.length
            if beforeStart >= 0 && afterEnd + markerLen <= str.length {
                let before = str.substring(with: NSRange(location: beforeStart, length: markerLen))
                let after = str.substring(with: NSRange(location: afterEnd, length: markerLen))
                if before == marker && after == marker {
                    // Unwrap
                    let fullRange = NSRange(location: beforeStart, length: sel.length + markerLen * 2)
                    insertText(selectedText, replacementRange: fullRange)
                    setSelectedRange(NSRange(location: beforeStart, length: sel.length))
                    return
                }
            }
            // Check if selection itself starts/ends with marker
            if selectedText.hasPrefix(marker) && selectedText.hasSuffix(marker) && selectedText.count > markerLen * 2 {
                let inner = String(selectedText.dropFirst(markerLen).dropLast(markerLen))
                insertText(inner, replacementRange: sel)
                setSelectedRange(NSRange(location: sel.location, length: inner.count))
                return
            }
            // Wrap selection
            let wrapped = "\(marker)\(selectedText)\(marker)"
            insertText(wrapped, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + markerLen, length: sel.length))
        } else {
            // Insert pair and position cursor between
            let pair = "\(marker)\(marker)"
            insertText(pair, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + markerLen, length: 0))
        }
    }

    // MARK: - List continuation

    func listContinuation(for lineText: String) -> String? {
        let nsLine = lineText as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        // Task list: - [ ] or - [x]
        let taskPattern = try! NSRegularExpression(pattern: "^(\\s*)- \\[[ x]\\]\\s")
        if let match = taskPattern.firstMatch(in: lineText, range: range) {
            let indent = nsLine.substring(with: match.range(at: 1))
            // Check if line is just the prefix with no content after
            let afterPrefix = nsLine.substring(from: NSMaxRange(match.range))
            if afterPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil // Signal to clear prefix
            }
            return "\(indent)- [ ] "
        }

        // Unordered list: - or * or +
        let ulPattern = try! NSRegularExpression(pattern: "^(\\s*)([-*+])\\s")
        if let match = ulPattern.firstMatch(in: lineText, range: range) {
            let indent = nsLine.substring(with: match.range(at: 1))
            let bullet = nsLine.substring(with: match.range(at: 2))
            let afterPrefix = nsLine.substring(from: NSMaxRange(match.range))
            if afterPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
            return "\(indent)\(bullet) "
        }

        // Ordered list: 1.
        let olPattern = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\.\\s")
        if let match = olPattern.firstMatch(in: lineText, range: range) {
            let indent = nsLine.substring(with: match.range(at: 1))
            let numStr = nsLine.substring(with: match.range(at: 2))
            let num = Int(numStr) ?? 1
            let afterPrefix = nsLine.substring(from: NSMaxRange(match.range))
            if afterPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                return nil
            }
            return "\(indent)\(num + 1). "
        }

        return nil // Not a list line
    }

    /// Returns the text of the current line (paragraph) containing the cursor.
    func currentLineText() -> (text: String, range: NSRange)? {
        guard let ts = textStorage else { return nil }
        let str = ts.string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: NSRange(location: sel.location, length: 0))
        let lineText = str.substring(with: lineRange)
        return (lineText, lineRange)
    }

    /// Returns just the prefix portion of a list line (for clearing empty continuations).
    func listPrefixRange(for lineRange: NSRange) -> NSRange? {
        guard let ts = textStorage else { return nil }
        let str = ts.string as NSString
        let lineText = str.substring(with: lineRange)
        let nsLine = lineText as NSString
        let range = NSRange(location: 0, length: nsLine.length)

        let patterns = [
            try! NSRegularExpression(pattern: "^\\s*- \\[[ x]\\]\\s"),
            try! NSRegularExpression(pattern: "^\\s*[-*+]\\s"),
            try! NSRegularExpression(pattern: "^\\s*\\d+\\.\\s")
        ]

        for pattern in patterns {
            if let match = pattern.firstMatch(in: lineText, range: range) {
                return NSRange(location: lineRange.location, length: match.range.length)
            }
        }
        return nil
    }
}
