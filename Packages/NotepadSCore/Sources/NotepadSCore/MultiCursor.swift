import Foundation

/// One of several carets or selections (VS Code-style multiple cursors). `head` is where the
/// caret is and what arrow keys move; `anchor` is the other end of the selection. Positions are
/// UTF-16 offsets, like `NSRange`.
public struct Cursor: Equatable, Sendable {
    public var anchor: Int
    public var head: Int

    public init(anchor: Int, head: Int) {
        self.anchor = anchor
        self.head = head
    }

    /// An empty selection: just a caret.
    public init(at location: Int) {
        self.init(anchor: location, head: location)
    }

    public var range: NSRange {
        NSRange(location: min(anchor, head), length: abs(head - anchor))
    }

    public var isEmpty: Bool { anchor == head }
}

/// Replace `range` (in the text before the edit) with `string`.
public struct TextReplacement: Equatable, Sendable {
    public var range: NSRange
    public var string: String

    public init(range: NSRange, string: String) {
        self.range = range
        self.string = string
    }
}

/// An edit at several cursors: replacements sorted by position and not overlapping, to be applied
/// together as one undo step, and the cursors afterwards (in the new text).
public struct MultiCursorEdit: Equatable, Sendable {
    public var replacements: [TextReplacement]
    public var cursors: [Cursor]
}

/// How arrow keys move a cursor.
public enum CursorMovement: Sendable {
    case left, right, up, down
    case wordLeft, wordRight
    case lineStart, lineEnd
}

/// Editing with several cursors at once: typing, deleting and moving at every cursor. Pure
/// functions on the text, so the editor only applies the result.
///
/// Lines are logical lines (`\n`, `\r\n`, `\r`, possibly mixed); a `\r\n` pair is one character
/// and a line break is never split. Columns count characters as you see them (an emoji is one).
public enum MultiCursor {

    /// Sorted by position; overlapping selections and carets at the same place are merged.
    public static func normalized(_ cursors: [Cursor]) -> [Cursor] {
        let sorted = cursors.sorted { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
        var result: [Cursor] = []
        for cursor in sorted {
            guard let last = result.last else {
                result.append(cursor)
                continue
            }
            let lastRange = last.range, range = cursor.range
            let overlaps = range.location < NSMaxRange(lastRange)
            let samePlace = range.location == lastRange.location && (range.length == 0 || lastRange.length == 0)
            if overlaps || samePlace {
                let start = lastRange.location, end = max(NSMaxRange(lastRange), NSMaxRange(range))
                result[result.count - 1] = start == end ? Cursor(at: start) : Cursor(anchor: start, head: end)
            } else {
                result.append(cursor)
            }
        }
        return result
    }

    // MARK: - Adding cursors

    /// Adds a caret on the line above the topmost cursor (or below the bottommost), at `column`
    /// or the end of that line if it is shorter. Returns nil if there is no such line.
    public static func addingCursor(to cursors: [Cursor], above: Bool, column: Int, in text: NSString) -> [Cursor]? {
        guard let edge = above ? cursors.min(by: { $0.head < $1.head }) : cursors.max(by: { $0.head < $1.head }),
              let lineStart = above ? previousLineStart(before: edge.head, in: text) : nextLineStart(after: edge.head, in: text)
        else { return nil }
        return normalized(cursors + [Cursor(at: location(atColumn: column, ofLineStartingAt: lineStart, in: text))])
    }

    // MARK: - Editing

    /// Replaces each cursor's selection (or inserts at its caret) with the string of the same
    /// index; afterwards each cursor is a caret after its new text. `cursors` must be normalized.
    public static func replacing(_ cursors: [Cursor], with strings: [String]) -> MultiCursorEdit {
        precondition(cursors.count == strings.count, "one string per cursor")
        var replacements: [TextReplacement] = []
        var result: [Cursor] = []
        var shift = 0   // how much earlier replacements moved this position
        for (cursor, string) in zip(cursors, strings) {
            let range = cursor.range
            let length = (string as NSString).length
            if range.length > 0 || length > 0 {
                replacements.append(TextReplacement(range: range, string: string))
            }
            result.append(Cursor(at: range.location + shift + length))
            shift += length - range.length
        }
        return MultiCursorEdit(replacements: replacements, cursors: result)
    }

    /// Deletes each selection, or for a caret the character (or word, with `byWord`) before it,
    /// or after it with `forward`. A caret at the edge of the text deletes nothing.
    public static func deleting(_ cursors: [Cursor], forward: Bool, byWord: Bool, in text: NSString) -> MultiCursorEdit {
        let ranges: [Cursor] = cursors.map { cursor in
            guard cursor.isEmpty else { return cursor }
            let target: Int
            switch (forward, byWord) {
            case (false, false): target = previousBoundary(before: cursor.head, in: text)
            case (true, false): target = nextBoundary(after: cursor.head, in: text)
            case (false, true): target = wordStart(before: cursor.head, in: text)
            case (true, true): target = wordEnd(after: cursor.head, in: text)
            }
            return Cursor(anchor: cursor.head, head: target)
        }
        // Two carets can reach into the same character; delete it once.
        let merged = normalized(ranges)
        return replacing(merged, with: Array(repeating: "", count: merged.count))
    }

    // MARK: - Moving

    /// Moves every cursor. With `extending` (Shift), the selection grows from its anchor;
    /// without, a selection collapses (left and up to its start, right and down to its end,
    /// as in other Mac text fields) and the caret moves from there.
    public static func moving(_ cursors: [Cursor], _ movement: CursorMovement, extending: Bool, in text: NSString) -> [Cursor] {
        normalized(cursors.map { cursor in
            if !extending, !cursor.isEmpty, movement == .left || movement == .right {
                let range = cursor.range
                return Cursor(at: movement == .left ? range.location : NSMaxRange(range))
            }
            let head = moved(cursor.head, movement, in: text)
            return extending ? Cursor(anchor: cursor.anchor, head: head) : Cursor(at: head)
        })
    }

    private static func moved(_ location: Int, _ movement: CursorMovement, in text: NSString) -> Int {
        switch movement {
        case .left:
            return previousBoundary(before: location, in: text)
        case .right:
            return nextBoundary(after: location, in: text)
        case .wordLeft:
            return wordStart(before: location, in: text)
        case .wordRight:
            return wordEnd(after: location, in: text)
        case .lineStart:
            return lineStart(of: location, in: text)
        case .lineEnd:
            return lineContentEnd(of: location, in: text)
        case .up, .down:
            let column = self.column(of: location, in: text)
            // On the first line Up goes to the start of the text, on the last Down to the end,
            // like every Mac text field.
            guard let start = movement == .up ? previousLineStart(before: location, in: text)
                                               : nextLineStart(after: location, in: text) else {
                return movement == .up ? 0 : text.length
            }
            return self.location(atColumn: column, ofLineStartingAt: start, in: text)
        }
    }

    // MARK: - Lines and columns

    /// The column of `location` in its line, 0-based, in characters as you see them.
    public static func column(of location: Int, in text: NSString) -> Int {
        let start = lineStart(of: location, in: text)
        return TextStatistics.characterCount(of: text, in: NSRange(location: start, length: location - start))
    }

    /// The position `column` characters into the line, or the end of its content if the line is shorter.
    static func location(atColumn column: Int, ofLineStartingAt start: Int, in text: NSString) -> Int {
        let end = lineContentEnd(of: start, in: text)
        var location = start
        var remaining = column
        while remaining > 0, location < end {
            location = nextBoundary(after: location, in: text)
            remaining -= 1
        }
        return min(location, end)
    }

    static func lineStart(of location: Int, in text: NSString) -> Int {
        var start = min(location, text.length)
        while start > 0, !isBreak(text.character(at: start - 1)) {
            start -= 1
        }
        return start
    }

    static func lineContentEnd(of location: Int, in text: NSString) -> Int {
        var end = min(location, text.length)
        while end < text.length, !isBreak(text.character(at: end)) {
            end += 1
        }
        return end
    }

    /// The start of the line after the one containing `location`, or nil on the last line.
    static func nextLineStart(after location: Int, in text: NSString) -> Int? {
        let end = lineContentEnd(of: location, in: text)
        guard end < text.length else { return nil }
        return nextBoundary(after: end, in: text)   // skips "\r\n" as one
    }

    /// The start of the line before the one containing `location`, or nil on the first line.
    static func previousLineStart(before location: Int, in text: NSString) -> Int? {
        let start = lineStart(of: location, in: text)
        guard start > 0 else { return nil }
        return lineStart(of: previousBoundary(before: start, in: text), in: text)
    }

    // MARK: - Characters and words

    /// The start of the character before `location`; "\r\n" is one character.
    static func previousBoundary(before location: Int, in text: NSString) -> Int {
        guard location > 0 else { return 0 }
        if location >= 2, text.character(at: location - 1) == 0x0A, text.character(at: location - 2) == 0x0D {
            return location - 2
        }
        return text.rangeOfComposedCharacterSequence(at: location - 1).location
    }

    /// The end of the character after `location`; "\r\n" is one character.
    static func nextBoundary(after location: Int, in text: NSString) -> Int {
        guard location < text.length else { return text.length }
        if text.character(at: location) == 0x0D, location + 1 < text.length, text.character(at: location + 1) == 0x0A {
            return location + 2
        }
        return NSMaxRange(text.rangeOfComposedCharacterSequence(at: location))
    }

    /// Like ⌥← in Mac text fields: skips spaces and punctuation, then the word before.
    static func wordStart(before location: Int, in text: NSString) -> Int {
        var position = location
        while position > 0, !isWordCharacter(before: position, in: text) {
            position = previousBoundary(before: position, in: text)
        }
        while position > 0, isWordCharacter(before: position, in: text) {
            position = previousBoundary(before: position, in: text)
        }
        return position
    }

    /// Like ⌥→ in Mac text fields: skips spaces and punctuation, then the word after.
    static func wordEnd(after location: Int, in text: NSString) -> Int {
        var position = location
        while position < text.length, !isWordCharacter(after: position, in: text) {
            position = nextBoundary(after: position, in: text)
        }
        while position < text.length, isWordCharacter(after: position, in: text) {
            position = nextBoundary(after: position, in: text)
        }
        return position
    }

    private static func isWordCharacter(before location: Int, in text: NSString) -> Bool {
        let start = previousBoundary(before: location, in: text)
        return isWord(text.substring(with: NSRange(location: start, length: location - start)))
    }

    private static func isWordCharacter(after location: Int, in text: NSString) -> Bool {
        let end = nextBoundary(after: location, in: text)
        return isWord(text.substring(with: NSRange(location: location, length: end - location)))
    }

    /// Letters (also accented ones), digits and "_" make up words.
    private static func isWord(_ character: String) -> Bool {
        guard let first = character.first else { return false }
        return first.isLetter || first.isNumber || first == "_"
    }

    private static func isBreak(_ unit: unichar) -> Bool {
        unit == 0x0A || unit == 0x0D
    }
}
