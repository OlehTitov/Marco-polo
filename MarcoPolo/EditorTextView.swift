import AppKit

final class EditorTextView: NSTextView {
    override func didChangeText() {
        super.didChangeText()
        centerSelectionIfNeeded(animated: false)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: flag)
        centerSelectionIfNeeded(animated: false)
    }

    func centerSelectionIfNeeded(animated: Bool) {
        guard let scrollView = enclosingScrollView,
              let clipView = scrollView.contentView as NSClipView?,
              let layoutManager,
              let textContainer else {
            return
        }

        let selectedRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        if rect.isEmpty {
            let fallbackGlyph = max(0, min(layoutManager.numberOfGlyphs - 1, glyphRange.location))
            rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: fallbackGlyph, length: 1), in: textContainer)
        }

        let insetRect = rect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
        let clipBounds = clipView.bounds
        let targetY = max(-contentInsets.top, insetRect.midY - (clipBounds.height / 2.0))
        let maxY = max(-contentInsets.top, bounds.height - clipBounds.height + contentInsets.bottom)
        let constrainedY = min(max(targetY, -contentInsets.top), maxY)
        let targetOrigin = NSPoint(x: clipBounds.origin.x, y: constrainedY)

        if animated {
            clipView.animator().setBoundsOrigin(targetOrigin)
        } else {
            clipView.setBoundsOrigin(targetOrigin)
        }

        scrollView.reflectScrolledClipView(clipView)
    }
}
