import XCTest
@testable import NotepadSCore

final class MultiCursorTests: XCTestCase {

    /// Applies `edit` to `text`.
    private func apply(_ edit: MultiCursorEdit, to text: String) -> String {
        let result = NSMutableString(string: text)
        for replacement in edit.replacements.reversed() {
            result.replaceCharacters(in: replacement.range, with: replacement.string)
        }
        return result as String
    }

    private func carets(_ locations: Int...) -> [Cursor] {
        locations.map { Cursor(at: $0) }
    }

    // MARK: - Normalizing

    func testNormalizedSortsAndMerges() {
        XCTAssertEqual(MultiCursor.normalized(carets(5, 1, 5)), carets(1, 5))
        XCTAssertEqual(MultiCursor.normalized([Cursor(anchor: 0, head: 3), Cursor(anchor: 5, head: 2)]),
                       [Cursor(anchor: 0, head: 5)], "overlapping selections")
        XCTAssertEqual(MultiCursor.normalized([Cursor(anchor: 0, head: 2), Cursor(at: 2)]).count, 2,
                       "a caret right after a selection stays separate")
    }

    // MARK: - Adding cursors

    func testAddCursorsBelowAndAboveAtTheSameColumn() {
        let text = "abcd\nab\r\nabcdef\rx" as NSString
        let below = MultiCursor.addingCursor(to: carets(2), above: false, column: 2, in: text)
        XCTAssertEqual(below, carets(2, 7))
        XCTAssertEqual(MultiCursor.addingCursor(to: below!, above: false, column: 2, in: text), carets(2, 7, 11))
        XCTAssertEqual(MultiCursor.addingCursor(to: carets(11), above: true, column: 2, in: text), carets(7, 11))
    }

    func testAddCursorOnAShorterLineGoesToItsEnd() {
        let text = "abcdef\nab\nabcdef" as NSString
        XCTAssertEqual(MultiCursor.addingCursor(to: carets(5), above: false, column: 5, in: text), carets(5, 9))
    }

    func testAddCursorCountsCharactersNotUTF16Units() {
        let text = "😀😀x\nabc" as NSString   // the x is at column 2, offset 4
        XCTAssertEqual(MultiCursor.addingCursor(to: carets(8), above: true, column: 2, in: text), carets(4, 8))
    }

    func testNoLineToAddACursorOn() {
        let text = "a\nb" as NSString
        XCTAssertNil(MultiCursor.addingCursor(to: carets(0), above: true, column: 0, in: text))
        XCTAssertNil(MultiCursor.addingCursor(to: carets(2), above: false, column: 0, in: text))
    }

    // MARK: - Typing

    func testTypingAtEveryCaret() {
        let edit = MultiCursor.replacing(carets(1, 4, 8), with: ["X", "X", "X"])
        XCTAssertEqual(apply(edit, to: "ab\ncd\r\nef"), "aXb\ncXd\r\neXf")
        XCTAssertEqual(edit.cursors, carets(2, 6, 11))
    }

    func testTypingReplacesSelectionsAndAcceptsDifferentStrings() {
        let cursors = [Cursor(anchor: 0, head: 2), Cursor(anchor: 5, head: 3)]
        let edit = MultiCursor.replacing(cursors, with: ["é", "😀😀"])
        XCTAssertEqual(apply(edit, to: "ab\ncd\n"), "é\n😀😀\n")
        XCTAssertEqual(edit.cursors, carets(1, 6))
    }

    // MARK: - Deleting

    func testBackspaceAtEveryCaretDeletesWholeCharacters() {
        let edit = MultiCursor.deleting(carets(0, 5, 9), forward: false, byWord: false, in: "ab\n😀c\r\ne" as NSString)
        XCTAssertEqual(apply(edit, to: "ab\n😀c\r\ne"), "ab\nc\r\n", "nothing before the first caret; the emoji and the e go")
        XCTAssertEqual(edit.cursors, carets(0, 3, 6))
    }

    func testBackspaceAtLineStartJoinsLinesAndTreatsCRLFAsOne() {
        let text = "a\r\nb\rc"
        let edit = MultiCursor.deleting(carets(3, 5), forward: false, byWord: false, in: text as NSString)
        XCTAssertEqual(apply(edit, to: text), "abc")
        XCTAssertEqual(edit.cursors, carets(1, 2))
    }

    func testDeleteForwardAndSelections() {
        let text = "abc\r\ndef"
        let edit = MultiCursor.deleting([Cursor(at: 3), Cursor(anchor: 5, head: 7)], forward: true, byWord: false,
                                        in: text as NSString)
        XCTAssertEqual(apply(edit, to: text), "abcf")
        XCTAssertEqual(edit.cursors, carets(3, 3))
    }

    func testCaretsDeletingTheSameCharacterDeleteItOnce() {
        let text = "abc"
        let edit = MultiCursor.deleting([Cursor(at: 1), Cursor(anchor: 2, head: 0)], forward: false, byWord: false,
                                        in: text as NSString)
        XCTAssertEqual(apply(edit, to: text), "c")
    }

    func testDeleteWordBackward() {
        let text = "foo bar, baz\nqux"
        let edit = MultiCursor.deleting(carets(7, 16), forward: false, byWord: true, in: text as NSString)
        XCTAssertEqual(apply(edit, to: text), "foo , baz\n")
    }

    // MARK: - Moving

    func testMoveLeftRightOverEmojiAndCRLF() {
        let text = "a😀\r\nb" as NSString
        XCTAssertEqual(MultiCursor.moving(carets(3, 6), .left, extending: false, in: text), carets(1, 5))
        XCTAssertEqual(MultiCursor.moving(carets(1, 3), .right, extending: false, in: text), carets(3, 5))
    }

    func testMovingCollapsesSelectionsAndShiftExtends() {
        let text = "abcdef" as NSString
        XCTAssertEqual(MultiCursor.moving([Cursor(anchor: 1, head: 3)], .left, extending: false, in: text), carets(1))
        XCTAssertEqual(MultiCursor.moving([Cursor(anchor: 1, head: 3)], .right, extending: true, in: text),
                       [Cursor(anchor: 1, head: 4)])
    }

    func testMoveUpDownKeepsTheColumnAndStopsAtTheEdges() {
        let text = "abc\r\nde\rfghi" as NSString
        XCTAssertEqual(MultiCursor.moving(carets(2, 11), .down, extending: false, in: text), carets(7, 12))
        XCTAssertEqual(MultiCursor.moving(carets(2, 11), .up, extending: false, in: text), carets(0, 7))
    }

    func testMergedWhenTwoCaretsMeet() {
        XCTAssertEqual(MultiCursor.moving(carets(0, 1), .left, extending: false, in: "ab" as NSString), carets(0))
    }

    func testLineStartEndAndWords() {
        let text = "  foo_bar(baz)\nnext" as NSString
        XCTAssertEqual(MultiCursor.moving(carets(5, 17), .lineStart, extending: false, in: text), carets(0, 15))
        XCTAssertEqual(MultiCursor.moving(carets(5, 17), .lineEnd, extending: false, in: text), carets(14, 19))
        XCTAssertEqual(MultiCursor.moving(carets(2), .wordRight, extending: false, in: text), carets(9))
        XCTAssertEqual(MultiCursor.moving(carets(13), .wordLeft, extending: false, in: text), carets(10))
    }

    func testColumnCountsCharacters() {
        XCTAssertEqual(MultiCursor.column(of: 5, in: "x\né😀b" as NSString), 2)
    }
}
