import Foundation

/// Counts for the status bar.
public enum TextStatistics {

    /// The number of user-perceived characters (grapheme clusters) in `range` of `text`:
    /// "é" written as e + combining accent, an emoji with skin tone, a flag and a CRLF line
    /// break each count as one, like Swift's `String.count`.
    ///
    /// Works on the `NSString` directly, so the editor can pass the text storage's
    /// `mutableString` without copying the document. Still O(n): call it for the whole
    /// document only when the text has stopped changing, not on every keystroke.
    /// An invalid range counts as 0.
    public static func characterCount(of text: NSString, in range: NSRange) -> Int {
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= text.length else { return 0 }
        let carriageReturn: unichar = 0x0D, lineFeed: unichar = 0x0A
        let end = NSMaxRange(range)
        var count = 0
        var location = range.location
        // Read the text in chunks: asking the NSString for one unit at a time is slow.
        let chunkSize = 4096
        var buffer = [unichar](repeating: 0, count: chunkSize + 1)
        while location < end {
            // One unit more than we step over, to see what follows the chunk's last unit.
            let chunk = NSRange(location: location, length: min(chunkSize + 1, end - location))
            text.getCharacters(&buffer, range: chunk)
            let stepEnd = location + min(chunkSize, chunk.length)
            while location < stepEnd {
                let unit = buffer[location - chunk.location]
                let nextIndex = location + 1 - chunk.location
                let next: unichar? = nextIndex < chunk.length ? buffer[nextIndex] : nil
                count += 1
                if unit < 0x80, next.map({ $0 < 0x80 }) ?? true {
                    // Fast path: between two ASCII characters there is always a character
                    // boundary, except inside CRLF, which counts as one character.
                    // (Combining marks, joiners, emoji are all outside ASCII.)
                    location += unit == carriageReturn && next == lineFeed ? 2 : 1
                } else {
                    // Foundation knows the Unicode rules for everything else. It treats CR and
                    // LF as separate sequences, but CRLF is handled by the fast path above.
                    location = NSMaxRange(text.rangeOfComposedCharacterSequence(at: location))
                }
            }
        }
        return count
    }
}
