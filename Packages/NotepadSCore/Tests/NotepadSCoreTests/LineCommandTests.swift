import XCTest
@testable import NotepadSCore

final class LineCommandTests: XCTestCase {

    /// Runs `command` on `text` with `selection` and returns the new text and selection, or nil
    /// if the command does nothing there.
    private func run(_ command: LineCommand, _ text: String, selection: NSRange,
                     lineEnding: LineEnding = .lf) -> (text: String, selection: NSRange)? {
        let string = text as NSString
        guard let edit = command.edit(in: string, lineIndex: LineIndex(text: string),
                                      selection: selection, lineEnding: lineEnding) else { return nil }
        let result = string.replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }

    private func caret(_ location: Int) -> NSRange {
        NSRange(location: location, length: 0)
    }

    // MARK: - Duplicate

    func testDuplicateCaretLine() {
        let result = run(.duplicate, "a\nb\nc", selection: caret(2))   // caret on "b"
        XCTAssertEqual(result?.text, "a\nb\nb\nc")
        XCTAssertEqual(result?.selection, caret(2), "the caret stays on the original line")
    }

    func testDuplicateLastLineWithoutBreakAddsTheDocumentsBreak() {
        XCTAssertEqual(run(.duplicate, "a\r\nb", selection: caret(3), lineEnding: .crlf)?.text, "a\r\nb\r\nb")
    }

    func testDuplicateKeepsEachLinesBreak() {
        XCTAssertEqual(run(.duplicate, "a\r\nb\rc", selection: NSRange(location: 0, length: 4))?.text,
                       "a\r\nb\ra\r\nb\rc", "lines a and b, with their own CRLF and CR")
    }

    func testDuplicateSelectionEndingAfterABreakDoesNotIncludeTheNextLine() {
        XCTAssertEqual(run(.duplicate, "a\nb\n", selection: NSRange(location: 0, length: 2))?.text, "a\na\nb\n")
    }

    func testDuplicateNonASCII() {
        XCTAssertEqual(run(.duplicate, "žluť😀\nx", selection: caret(1))?.text, "žluť😀\nžluť😀\nx")
    }

    func testDuplicateEmptyDocument() {
        XCTAssertEqual(run(.duplicate, "", selection: caret(0))?.text, "\n")
    }

    // MARK: - Delete

    func testDeleteCaretLine() {
        let result = run(.delete, "a\nb\nc", selection: caret(3))
        XCTAssertEqual(result?.text, "a\nc")
        XCTAssertEqual(result?.selection, caret(2), "start of the line that moved up")
    }

    func testDeleteLastLineRemovesTheBreakBeforeIt() {
        let result = run(.delete, "a\r\nb", selection: caret(4))
        XCTAssertEqual(result?.text, "a")
        XCTAssertEqual(result?.selection, caret(0))
    }

    func testDeleteSelectedLines() {
        XCTAssertEqual(run(.delete, "a\nb\rc\r\nd", selection: NSRange(location: 2, length: 3))?.text, "a\nd")
    }

    func testDeleteOnlyLine() {
        XCTAssertEqual(run(.delete, "abc", selection: caret(1))?.text, "")
    }

    func testDeleteEmptyLastLineAfterTrailingBreak() {
        XCTAssertEqual(run(.delete, "a\nb\n", selection: caret(4))?.text, "a\nb")
    }

    func testDeleteInEmptyDocumentDoesNothing() {
        XCTAssertNil(run(.delete, "", selection: caret(0)))
    }

    // MARK: - Move up

    func testMoveUp() {
        let result = run(.moveUp, "a\nbb\nc", selection: caret(3))   // caret after the first "b"
        XCTAssertEqual(result?.text, "bb\na\nc")
        XCTAssertEqual(result?.selection, caret(1), "same place within the moved line")
    }

    func testMoveUpKeepsSelectionLength() {
        let result = run(.moveUp, "a\nbc\nde\nf", selection: NSRange(location: 3, length: 3))   // "c\nd"
        XCTAssertEqual(result?.text, "bc\nde\na\nf")
        XCTAssertEqual(result?.selection, NSRange(location: 1, length: 3))
    }

    func testMoveUpLastLineWithoutBreak() {
        // The moved line gets the document's break; the line now last keeps none.
        XCTAssertEqual(run(.moveUp, "a\r\nb", selection: caret(3), lineEnding: .crlf)?.text, "b\r\na")
    }

    func testMoveUpKeepsEachLinesBreak() {
        XCTAssertEqual(run(.moveUp, "a\r\nb\rc", selection: caret(3))?.text, "b\ra\r\nc")
    }

    func testMoveUpFirstLineDoesNothing() {
        XCTAssertNil(run(.moveUp, "a\nb", selection: caret(0)))
    }

    func testMoveUpEmptyLastLineDoesNothing() {
        XCTAssertNil(run(.moveUp, "a\n", selection: caret(2)))
    }

    // MARK: - Move down

    func testMoveDown() {
        let result = run(.moveDown, "aa\nb\nc", selection: caret(1))
        XCTAssertEqual(result?.text, "b\naa\nc")
        XCTAssertEqual(result?.selection, caret(3))
    }

    func testMoveDownOntoLastLineWithoutBreak() {
        let result = run(.moveDown, "a\nb", selection: caret(0))
        XCTAssertEqual(result?.text, "b\na")
        XCTAssertEqual(result?.selection, caret(2))
    }

    func testMoveDownKeepsEachLinesBreakAndEmoji() {
        let result = run(.moveDown, "😀\r\nb\rc", selection: caret(2))   // caret after the emoji
        XCTAssertEqual(result?.text, "b\r😀\r\nc")
        XCTAssertEqual(result?.selection, caret(4))
    }

    func testMoveDownLastLineDoesNothing() {
        XCTAssertNil(run(.moveDown, "a\nb", selection: caret(2)))
    }

    func testMoveDownNeverPassesTheEmptyLastLine() {
        XCTAssertNil(run(.moveDown, "a\nb\n", selection: caret(2)))
    }
}
