import AppKit

final class FencedCodeTracker {
    /// Sorted array of NSRange pairs: [openFence, closeFence, openFence, closeFence, ...]
    /// Unpaired open fences extend to end of document.
    private(set) var fenceRanges: [(open: NSRange, close: NSRange?)] = []

    private let fencePattern = try! NSRegularExpression(pattern: "^```")

    /// Full scan of the backing text storage. Call on document load.
    func rebuild(from textStorage: NSTextStorage) {
        fenceRanges.removeAll()
        let string = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: string.length)

        var fenceLines: [NSRange] = []
        string.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let substring else { return }
            let lineRange = NSRange(location: 0, length: (substring as NSString).length)
            if self.fencePattern.firstMatch(in: substring, range: lineRange) != nil {
                fenceLines.append(substringRange)
            }
        }

        // Pair fences
        var i = 0
        while i < fenceLines.count {
            let open = fenceLines[i]
            if i + 1 < fenceLines.count {
                let close = fenceLines[i + 1]
                fenceRanges.append((open: open, close: close))
                i += 2
            } else {
                // Unpaired open fence — extends to end
                fenceRanges.append((open: open, close: nil))
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
                // Between open and close fence (exclusive of fence lines)
                if paragraphLocation >= openEnd && paragraphLocation < close.location {
                    return true
                }
            } else {
                // Unpaired — everything after the open fence
                if paragraphLocation >= openEnd {
                    return true
                }
            }
        }
        return false
    }
}
