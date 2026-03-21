import AppKit

final class HeadingLayoutFragment: NSTextLayoutFragment {
    let headingLevel: Int
    let headingFont: NSFont
    private let _leadingPadding: CGFloat

    init(textElement: NSTextElement, range: NSTextRange?,
         headingLevel: Int, headingFont: NSFont) {
        self.headingLevel = headingLevel
        self.headingFont = headingFont

        let prefixText = String(repeating: "#", count: headingLevel)
        let prefixWidth = (prefixText as NSString).size(withAttributes: [.font: headingFont]).width
        let gap: CGFloat = 8
        self._leadingPadding = prefixWidth + gap

        super.init(textElement: textElement, range: range)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var leadingPadding: CGFloat { _leadingPadding }

    override func draw(at point: CGPoint, in context: CGContext) {
        // Draw # decoration right-aligned in the leading padding area
        let prefixText = String(repeating: "#", count: headingLevel)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: headingFont,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let prefixSize = (prefixText as NSString).size(withAttributes: attrs)
        let gap: CGFloat = 8
        let drawX = point.x + leadingPadding - prefixSize.width - gap

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext
        (prefixText as NSString).draw(at: NSPoint(x: drawX, y: point.y), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        super.draw(at: point, in: context)
    }
}
