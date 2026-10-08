import Foundation

/// Overwrite mode (OVR): typed characters replace the characters after the caret instead of
/// pushing them to the right.
public enum Overwrite {

    /// The range that typing `characterCount` user-perceived characters at `caret` replaces:
    /// as many whole characters after the caret (an emoji or "e" + accent counts as one),
    /// stopping at the end of the line. Line breaks (`\n`, `\r\n`, `\r`) are never replaced, so
    /// typing at the end of a line makes the line longer, as in Notepad++.
    ///
    /// Positions are UTF-16 offsets, like `NSRange`. The range is empty at the end of a line or
    /// of the text; `caret` is clamped to the text.
    public static func rangeReplaced(byTyping characterCount: Int, at caret: Int, in text: NSString) -> NSRange {
        let start = min(max(caret, 0), text.length)
        var end = start
        var remaining = characterCount
        while remaining > 0, end < text.length {
            let unit = text.character(at: end)
            if unit == 0x0A || unit == 0x0D { break }
            end = NSMaxRange(text.rangeOfComposedCharacterSequence(at: end))
            remaining -= 1
        }
        return NSRange(location: start, length: end - start)
    }
}
