import AppKit

final class MarkdownTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()

    override var string: String {
        backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        let delta = (str as NSString).length - range.length
        edited([.editedCharacters, .editedAttributes], range: range, changeInLength: delta)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        let paragraphRange = (string as NSString).paragraphRange(for: editedRange)
        applyStyles(to: paragraphRange)
        super.processEditing()
    }

    private func applyStyles(to range: NSRange) {
        guard range.location != NSNotFound else { return }

        let nsString = string as NSString
        let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        backingStore.beginEditing()
        backingStore.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ], range: range)

        nsString.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, paragraphRange, _, _ in
            let line = nsString.substring(with: paragraphRange)
            let headingLevel = Self.headingLevel(for: line)
            guard headingLevel > 0 else { return }

            let scale = Self.fontScale(for: headingLevel)
            let font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * scale, weight: .bold)
            let headingStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            headingStyle.paragraphSpacingBefore = headingLevel == 1 ? 8 : 4
            headingStyle.paragraphSpacing = 6

            backingStore.addAttributes([
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: headingStyle
            ], range: paragraphRange)
        }
        backingStore.endEditing()
    }

    private static func headingLevel(for line: String) -> Int {
        var count = 0
        for character in line {
            if character == "#" {
                count += 1
            } else {
                break
            }
        }

        guard count > 0, count <= 6 else { return 0 }
        let index = line.index(line.startIndex, offsetBy: count, limitedBy: line.endIndex) ?? line.endIndex
        return index < line.endIndex && line[index] == " " ? count : 0
    }

    private static func fontScale(for headingLevel: Int) -> CGFloat {
        switch headingLevel {
        case 1: return 1.9
        case 2: return 1.6
        case 3: return 1.4
        case 4: return 1.25
        case 5: return 1.15
        default: return 1.05
        }
    }
}
