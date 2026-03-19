import AppKit

final class MarkdownStyling: NSObject, NSTextContentStorageDelegate {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private let baseParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        return style
    }()

    func textContentStorage(
        _ textContentStorage: NSTextContentStorage,
        textParagraphWith range: NSRange
    ) -> NSTextParagraph? {
        guard let originalText = textContentStorage.textStorage?.attributedSubstring(from: range) else {
            return nil
        }

        let line = originalText.string
        let fullRange = NSRange(location: 0, length: (line as NSString).length)
        let styled = NSMutableAttributedString(string: line)

        styled.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: baseParagraphStyle
        ], range: fullRange)

        let headingLevel = Self.headingLevel(for: line)
        if headingLevel > 0 {
            let scale = Self.fontScale(for: headingLevel)
            let font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * scale, weight: .bold)
            let headingStyle = baseParagraphStyle.mutableCopy() as! NSMutableParagraphStyle
            headingStyle.paragraphSpacingBefore = headingLevel == 1 ? 8 : 4
            headingStyle.paragraphSpacing = 6

            styled.addAttributes([
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: headingStyle
            ], range: fullRange)
        }

        return NSTextParagraph(attributedString: styled)
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
