import Foundation

/// Which lines an edit replaced: lines `firstLine...oldLastLine` of the old text became lines
/// `firstLine...newLastLine` of the new text. Lines after them are unchanged (only renumbered).
public struct LineChange: Equatable, Sendable {
    public let firstLine: Int
    public let oldLastLine: Int
    public let newLastLine: Int

    public var lineCountDelta: Int { newLastLine - oldLastLine }
}

extension LineIndex {
    /// `applyEdit`, plus which lines changed, for `Highlighter.linesChanged(_:)`.
    ///
    /// Starts one line before the edit: inserting `\n` right after a `\r` (or deleting text
    /// between them) joins two lines into one, which also changes the previous line's break.
    public mutating func applyEditReportingLines(editedRange: NSRange, changeInLength: Int,
                                                 in text: NSString) -> LineChange {
        let firstLine = max(line(containing: editedRange.location) - 1, 0)
        let oldLastLine = line(containing: NSMaxRange(editedRange) - changeInLength)
        applyEdit(editedRange: editedRange, changeInLength: changeInLength, in: text)
        let newLastLine = max(line(containing: NSMaxRange(editedRange)), firstLine)
        return LineChange(firstLine: firstLine, oldLastLine: oldLastLine, newLastLine: newLastLine)
    }
}

/// Colors a document line by line, remembering the tokenizer state at the start of each line.
///
/// Why per-line state: a block comment, a Python `"""` string or a Markdown code fence can span
/// many lines, so how a line is colored depends on the lines before it. Tokenizing from the
/// top for every keystroke would be too slow, and tokenizing only the edited line would get
/// multi-line constructs wrong. Instead, after an edit the highlighter re-tokenizes from the
/// edited line onward and stops as soon as a line past the edit starts in the same state as
/// before ("the state stabilized"): everything after it is colored as it was.
///
/// States are computed lazily, only as far down as someone asks for tokens.
public final class Highlighter {

    public let grammar: Grammar

    /// The tokenizer state at the start of each line; nil where it was never computed.
    /// Entries at `validLineCount` and beyond may be stale; they are kept as hints for
    /// detecting that the state stabilized.
    private var startStates: [LineState?]
    /// `startStates[0..<validLineCount]` are correct for the current text.
    private var validLineCount = 1
    /// The last line changed by edits that haven't been re-tokenized yet.
    private var lastEditedLine: Int?

    /// - Parameter lineCount: the document's number of lines (`LineIndex.lineCount`).
    public init(grammar: Grammar, lineCount: Int) {
        self.grammar = grammar
        startStates = [.initial] + Array(repeating: nil, count: max(lineCount, 1) - 1)
    }

    public var lineCount: Int { startStates.count }

    /// Tells the highlighter about an edit. Call it for every change of the text, with the
    /// result of `LineIndex.applyEditReportingLines`.
    public func linesChanged(_ change: LineChange) {
        let first = change.firstLine
        if validLineCount > first + 1 && validLineCount < startStates.count {
            // The stored states after the valid lines are hints from before the last time valid
            // states changed; once more valid states become hints, the two groups no longer fit
            // together, and an older hint could wrongly look like the state stabilized.
            startStates.replaceSubrange(validLineCount..., with: repeatElement(nil, count: startStates.count - validLineCount))
        }
        // The start state of `first` doesn't depend on the edit; the lines after it do.
        startStates.replaceSubrange((first + 1)..<(change.oldLastLine + 1),
                                    with: repeatElement(nil, count: change.newLastLine - first))
        validLineCount = min(validLineCount, first + 1)
        if let previous = lastEditedLine, previous > change.oldLastLine {
            lastEditedLine = previous + change.lineCountDelta   // an earlier edit further down
        } else {
            lastEditedLine = change.newLastLine
        }
    }

    /// Tokens of `lines`, with ranges relative to the start of the text (ready for
    /// `NSLayoutManager`). Computes the start states of earlier lines first if needed.
    public func tokens(forLines lines: Range<Int>, in text: NSString, lineIndex: LineIndex) -> [SyntaxToken] {
        let lines = lines.clamped(to: 0..<lineCount)
        guard let lastLine = lines.last else { return [] }
        updateStartStates(through: lastLine, in: text, lineIndex: lineIndex)

        var tokens: [SyntaxToken] = []
        for line in lines {
            let content = lineIndex.contentRange(ofLine: line)
            let lineText = text.substring(with: content) as NSString
            for token in grammar.tokenize(line: lineText, startingIn: state(ofLine: line)).tokens {
                tokens.append(SyntaxToken(range: NSRange(location: token.range.location + content.location,
                                                         length: token.range.length),
                                          scope: token.scope))
            }
        }
        return tokens
    }

    /// Makes the start states of lines `0...line` correct. Returns how many lines it tokenized
    /// (for tests and diagnostics).
    @discardableResult
    public func updateStartStates(through line: Int, in text: NSString, lineIndex: LineIndex) -> Int {
        precondition(lineIndex.lineCount == lineCount, "Highlighter missed an edit (call linesChanged)")
        var tokenizedLines = 0
        while validLineCount <= min(line, lineCount - 1) {
            let current = validLineCount - 1
            let lineText = text.substring(with: lineIndex.contentRange(ofLine: current)) as NSString
            let endState = grammar.tokenize(line: lineText, startingIn: state(ofLine: current)).endState
            tokenizedLines += 1

            let next = current + 1
            let previousHint = startStates[next]
            startStates[next] = endState
            validLineCount = next + 1

            if let lastEditedLine, next > lastEditedLine, previousHint == endState {
                // Past all edits, and this line starts exactly as before: the stored states of
                // the following lines are still correct, as far as they were computed.
                self.lastEditedLine = nil
                validLineCount = startStates[next...].firstIndex(where: { $0 == nil }) ?? lineCount
            }
        }
        if validLineCount == lineCount {
            lastEditedLine = nil
        }
        return tokenizedLines
    }

    /// The start state of a line whose state is known to be correct.
    private func state(ofLine line: Int) -> LineState {
        // Callers only ask for lines below `validLineCount`, whose states are all computed.
        guard let state = startStates[line] else {
            preconditionFailure("Start state of line \(line) requested before it was computed")
        }
        return state
    }
}
