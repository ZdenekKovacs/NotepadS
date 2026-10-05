import XCTest
@testable import NotepadSCore

final class HighlighterTests: XCTestCase {

    private let grammar = Grammar(name: "Test", rules: [
        .span("/\\*", "\\*/", .comment),
        .match("\\b\\d+\\b", .number),
    ])

    /// A document being edited, kept in sync the way the editor does it.
    private final class Document {
        let text: NSMutableString
        var lineIndex: LineIndex
        let highlighter: Highlighter

        init(_ string: String, grammar: Grammar) {
            text = NSMutableString(string: string)
            lineIndex = LineIndex(text: text)
            highlighter = Highlighter(grammar: grammar, lineCount: lineIndex.lineCount)
        }

        func replace(_ range: NSRange, with string: String) {
            text.replaceCharacters(in: range, with: string)
            let length = (string as NSString).length
            let change = lineIndex.applyEditReportingLines(editedRange: NSRange(location: range.location, length: length),
                                                           changeInLength: length - range.length, in: text)
            highlighter.linesChanged(change)
        }

        /// Replaces the whole content of one line (without its break).
        func replaceLine(_ line: Int, with string: String) {
            replace(lineIndex.contentRange(ofLine: line), with: string)
        }

        @discardableResult
        func updateAll() -> Int {
            highlighter.updateStartStates(through: lineIndex.lineCount - 1, in: text, lineIndex: lineIndex)
        }

        func scopes(ofLine line: Int) -> [SyntaxScope] {
            highlighter.tokens(forLines: line..<(line + 1), in: text, lineIndex: lineIndex).map(\.scope)
        }
    }

    private func document(lines: Int) -> Document {
        Document(Array(repeating: "x = 1", count: lines).joined(separator: "\n"), grammar: grammar)
    }

    func testFirstPassTokenizesEveryLineOnce() {
        let document = document(lines: 1000)
        XCTAssertEqual(document.updateAll(), 999, "the last line's end state isn't needed")
        XCTAssertEqual(document.updateAll(), 0, "nothing to do without edits")
    }

    func testEditThatKeepsTheStateStopsRightAway() {
        let document = document(lines: 1000)
        document.updateAll()
        document.replaceLine(500, with: "x = 2")
        XCTAssertLessThanOrEqual(document.updateAll(), 2)
        XCTAssertEqual(document.scopes(ofLine: 900), [.number])
    }

    func testOpeningACommentRetokenizesUntilTheEnd() {
        let document = document(lines: 1000)
        document.updateAll()
        document.replaceLine(500, with: "x = /* 1")
        XCTAssertEqual(document.updateAll(), 500, "from the line before the edit to the end")
        XCTAssertEqual(document.scopes(ofLine: 900), [.comment])
        XCTAssertEqual(document.scopes(ofLine: 499), [.number])

        // Closing it 100 lines later only re-tokenizes until the old state shows up again.
        document.replaceLine(600, with: "*/ 1")
        XCTAssertLessThanOrEqual(document.updateAll(), 2 + 399, "re-tokenizes from 600 on, states differ again")
        XCTAssertEqual(document.scopes(ofLine: 900), [.number])
        XCTAssertEqual(document.scopes(ofLine: 550), [.comment])
    }

    func testClosingTheOnlyCommentStabilizesQuickly() {
        let document = document(lines: 1000)
        document.replaceLine(500, with: "/* 1")
        document.replaceLine(501, with: "1 */")
        document.updateAll()
        // Editing inside the comment doesn't change any line's start state after it.
        document.replaceLine(500, with: "/* 2")
        XCTAssertLessThanOrEqual(document.updateAll(), 2)
        XCTAssertEqual(document.scopes(ofLine: 502), [.number])
    }

    func testOnlyRequestedLinesAreTokenized() {
        let document = document(lines: 10_000)
        let tokens = document.highlighter.tokens(forLines: 0..<50, in: document.text, lineIndex: document.lineIndex)
        XCTAssertEqual(tokens.count, 50)
        XCTAssertEqual(tokens[1].range, NSRange(location: 10, length: 1), "ranges are relative to the whole text")
        XCTAssertLessThanOrEqual(document.highlighter.updateStartStates(through: 49, in: document.text,
                                                                        lineIndex: document.lineIndex), 0)
    }

    func testEditsBeforeTheFirstPass() {
        let document = document(lines: 100)
        document.replaceLine(10, with: "/*")
        document.replaceLine(20, with: "*/")
        document.updateAll()
        XCTAssertEqual(document.scopes(ofLine: 15), [.comment])
        XCTAssertEqual(document.scopes(ofLine: 30), [.number])
    }

    /// Random edits (with line breaks of every style and comment delimiters) checked against a
    /// highlighter built from scratch for the same text.
    func testRandomEditsMatchFreshHighlighter() {
        var generator = SeededGenerator(seed: 42)
        let pieces = ["x", "1", " ", "/*", "*/", "\n", "\r\n", "\r", "é", "😀"]
        let document = Document("", grammar: grammar)

        for step in 0..<5_000 {
            let location = Int.random(in: 0...document.text.length, using: &generator)
            let length = Int.random(in: 0...min(document.text.length - location, 5), using: &generator)
            var insertion = ""
            for _ in 0..<Int.random(in: 0...3, using: &generator) {
                insertion += pieces.randomElement(using: &generator)!   // non-empty array
            }
            document.replace(NSRange(location: location, length: length), with: insertion)
            XCTAssertEqual(document.highlighter.lineCount, document.lineIndex.lineCount)

            // Sometimes look at the whole text, sometimes only at a few lines, like scrolling.
            let lastLine = document.lineIndex.lineCount - 1
            let visible = step % 3 == 0 ? 0..<(lastLine + 1)
                                        : 0..<Int.random(in: 1...(lastLine + 1), using: &generator)
            let actual = document.highlighter.tokens(forLines: visible, in: document.text, lineIndex: document.lineIndex)
            let fresh = Highlighter(grammar: grammar, lineCount: document.lineIndex.lineCount)
            let expected = fresh.tokens(forLines: visible, in: document.text, lineIndex: document.lineIndex)
            if actual != expected {
                XCTFail("Mismatch after step \(step): \(String(reflecting: document.text as String))")
                return
            }
            if document.text.length > 300 {
                document.replace(NSRange(location: 0, length: document.text.length), with: "")
            }
        }
    }
}
