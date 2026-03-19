import AppKit

final class FencedCodeTracker {
    /// Sorted array of fence pairs with optional language from opening fence.
    /// Unpaired open fences extend to end of document.
    private(set) var fenceRanges: [(open: NSRange, close: NSRange?, language: String?)] = []

    private let fencePattern = try! NSRegularExpression(pattern: "^```(\\w+)?\\s*$")

    /// Full scan of the backing text storage. Call on document load.
    func rebuild(from textStorage: NSTextStorage) {
        fenceRanges.removeAll()
        let string = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)

        var fenceLines: [(range: NSRange, language: String?)] = []
        string.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring else { return }
            let lineRange = NSRange(location: 0, length: (substring as NSString).length)
            if let match = self.fencePattern.firstMatch(in: substring, range: lineRange) {
                let langRange = match.range(at: 1)
                let language: String? = langRange.location != NSNotFound ? (substring as NSString).substring(with: langRange) : nil
                fenceLines.append((range: substringRange, language: language))
            }
        }

        // Pair fences — opening fence captures language, closing fence does not
        var i = 0
        while i < fenceLines.count {
            let open = fenceLines[i]
            if i + 1 < fenceLines.count {
                let close = fenceLines[i + 1]
                fenceRanges.append((open: open.range, close: close.range, language: open.language))
                i += 2
            } else {
                // Unpaired open fence — extends to end
                fenceRanges.append((open: open.range, close: nil, language: open.language))
                i += 1
            }
        }
    }

    /// Returns true if the given paragraph range falls inside a fenced code block (between open/close fences).
    /// The fence lines themselves return false — they are styled as fences, not body.
    func isInsideFencedCode(paragraphLocation: Int) -> Bool {
        for pair in fenceRanges {
            let openEnd = NSMaxRange(pair.open)
            if let close = pair.close {
                if paragraphLocation >= openEnd && paragraphLocation < close.location {
                    return true
                }
            } else {
                if paragraphLocation >= openEnd {
                    return true
                }
            }
        }
        return false
    }

    /// Returns the language and the NSRange of the code content (between open and close fences, exclusive)
    /// for the code block containing the paragraph at the given location.
    func codeBlockInfo(forParagraphAt location: Int) -> (language: String?, openLocation: Int, codeRange: NSRange)? {
        for pair in fenceRanges {
            let openEnd = NSMaxRange(pair.open)
            if let close = pair.close {
                if location >= openEnd && location < close.location {
                    let codeRange = NSRange(location: openEnd, length: close.location - openEnd)
                    return (language: pair.language, openLocation: pair.open.location, codeRange: codeRange)
                }
            } else {
                // Unpaired — no close fence, can't reliably determine end
                // Return nil so we fall back to default styling
                if location >= openEnd {
                    return (language: pair.language, openLocation: pair.open.location, codeRange: NSRange(location: openEnd, length: 0))
                }
            }
        }
        return nil
    }
}
