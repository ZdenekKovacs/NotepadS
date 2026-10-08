import Foundation

/// A change to the text that a line command computed, ready for the editor to apply as one
/// undo step.
public struct LineEdit: Equatable, Sendable {
    /// The range of the current text to replace (UTF-16 offsets).
    public var range: NSRange
    public var replacement: String
    /// The selection after the change, in the new text.
    public var selection: NSRange
}

/// Commands on the lines the caret or selection is on (Text › Lines): duplicate, delete,
/// move up, move down.
///
/// They work on whole lines: the caret's line, or every line the selection touches (a selection
/// ending right after a line break doesn't include the next line). Every line keeps its own
/// line break; only a line that had none (the last line) and moves into the middle gets the
/// document's style.
public enum LineCommand: Sendable {
    case duplicate
    case delete
    case moveUp
    case moveDown

    /// The edit for this command, or nil if it changes nothing (e.g. moving the first line up).
    /// `lineIndex` must be up to date for `text`.
    public func edit(in text: NSString, lineIndex: LineIndex, selection: NSRange, lineEnding: LineEnding) -> LineEdit? {
        let selection = NSRange(location: min(selection.location, text.length),
                                length: min(selection.length, text.length - min(selection.location, text.length)))
        let firstLine = lineIndex.line(containing: selection.location)
        let lastLine = selection.length > 0 ? lineIndex.line(containing: NSMaxRange(selection) - 1) : firstLine
        let block = NSRange(location: lineIndex.lineStart(of: firstLine),
                            length: NSMaxRange(lineIndex.fullRange(ofLine: lastLine)) - lineIndex.lineStart(of: firstLine))
        let blockEndsWithBreak = lineIndex.fullRange(ofLine: lastLine).length > lineIndex.contentRange(ofLine: lastLine).length

        switch self {
        case .duplicate:
            // The copy goes after the block, so the caret stays on the original lines.
            let blockText = text.substring(with: block)
            return LineEdit(range: NSRange(location: NSMaxRange(block), length: 0),
                            replacement: blockEndsWithBreak ? blockText : lineEnding.string + blockText,
                            selection: selection)

        case .delete:
            guard text.length > 0 else { return nil }
            if blockEndsWithBreak || firstLine == 0 {
                return LineEdit(range: block, replacement: "", selection: NSRange(location: block.location, length: 0))
            }
            // The last line has no break: remove the break before it, so no empty line is left.
            let start = NSMaxRange(lineIndex.contentRange(ofLine: firstLine - 1))
            return LineEdit(range: NSRange(location: start, length: NSMaxRange(block) - start), replacement: "",
                            selection: NSRange(location: lineIndex.lineStart(of: firstLine - 1), length: 0))

        case .moveUp:
            // The empty line after a final line break isn't a line that can move.
            guard firstLine > 0, block.location < text.length else { return nil }
            let range = NSRange(location: lineIndex.lineStart(of: firstLine - 1),
                                length: NSMaxRange(block) - lineIndex.lineStart(of: firstLine - 1))
            let lines = TextLines(text.substring(with: range))
            let moved = lines.reordered(Array(lines.lines.dropFirst()) + [lines.lines[0]], lineEnding: lineEnding)
            let newText = moved.text
            let location = range.location + (selection.location - block.location)
            return LineEdit(range: range, replacement: newText,
                            selection: Self.clamped(location: location, length: selection.length,
                                                    to: range.location + (newText as NSString).length))

        case .moveDown:
            guard lastLine + 1 < lineIndex.lineCount, lineIndex.lineStart(of: lastLine + 1) < text.length else { return nil }
            let range = NSRange(location: block.location,
                                length: NSMaxRange(lineIndex.fullRange(ofLine: lastLine + 1)) - block.location)
            let lines = TextLines(text.substring(with: range))
            let moved = lines.reordered([lines.lines[lines.lines.count - 1]] + lines.lines.dropLast(), lineEnding: lineEnding)
            let newText = moved.text
            // The line that moved up now comes first; the selection follows the block below it.
            let lineAbove = moved.lines[0]
            let shift = (lineAbove.content as NSString).length + (lineAbove.terminator as NSString).length
            let location = selection.location + shift
            return LineEdit(range: range, replacement: newText,
                            selection: Self.clamped(location: location, length: selection.length,
                                                    to: range.location + (newText as NSString).length))
        }
    }

    /// A selection of `length` at `location`, cut off at `end` (a moved last line may have lost
    /// its break, so the block can be shorter than before).
    private static func clamped(location: Int, length: Int, to end: Int) -> NSRange {
        let location = min(location, end)
        return NSRange(location: location, length: min(length, end - location))
    }
}
