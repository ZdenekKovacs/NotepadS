import XCTest
@testable import NotepadSCore

final class OverwriteTests: XCTestCase {

    /// The text that `range` covers, to keep the expectations readable.
    private func replaced(typing count: Int, at caret: Int, in text: String) -> String {
        let string = text as NSString
        return string.substring(with: Overwrite.rangeReplaced(byTyping: count, at: caret, in: string))
    }

    func testReplacesTheNextCharacter() {
        XCTAssertEqual(replaced(typing: 1, at: 0, in: "abc"), "a")
        XCTAssertEqual(replaced(typing: 1, at: 2, in: "abc"), "c")
    }

    func testReplacesOneCharacterPerTypedCharacter() {
        XCTAssertEqual(replaced(typing: 2, at: 1, in: "abcd"), "bc")
    }

    func testNothingIsReplacedForNothingTyped() {
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 0, at: 1, in: "abc"), NSRange(location: 1, length: 0))
    }

    func testEndOfDocumentInserts() {
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 3, in: "abc"), NSRange(location: 3, length: 0))
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 0, in: ""), NSRange(location: 0, length: 0))
    }

    /// Typing at the end of a line extends the line; line breaks of every style are kept.
    func testLineBreaksAreNeverReplaced() {
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 1, in: "a\nb"), NSRange(location: 1, length: 0))
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 1, in: "a\r\nb"), NSRange(location: 1, length: 0))
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 1, in: "a\rb"), NSRange(location: 1, length: 0))
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 2, in: "a\r\nb"), NSRange(location: 2, length: 0),
                       "between CR and LF")
    }

    func testStopsAtTheLineBreak() {
        XCTAssertEqual(replaced(typing: 5, at: 1, in: "abc\r\nxyz"), "bc")
        XCTAssertEqual(replaced(typing: 5, at: 0, in: "ab\rcd"), "ab")
    }

    /// An emoji, a flag or a letter with a combining accent is one character, so one keystroke
    /// replaces all of its UTF-16 units and never leaves half of it behind.
    func testReplacesWholeCharacters() {
        XCTAssertEqual(replaced(typing: 1, at: 1, in: "a😀b"), "😀")
        XCTAssertEqual(replaced(typing: 1, at: 0, in: "🇨🇿x"), "🇨🇿")
        XCTAssertEqual(replaced(typing: 1, at: 0, in: "e\u{301}x"), "e\u{301}")
        XCTAssertEqual(replaced(typing: 2, at: 0, in: "žluť"), "žl")
    }

    func testCaretOutsideTheTextIsClamped() {
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: 10, in: "abc"), NSRange(location: 3, length: 0))
        XCTAssertEqual(Overwrite.rangeReplaced(byTyping: 1, at: -1, in: "abc"), NSRange(location: 0, length: 1))
    }
}
