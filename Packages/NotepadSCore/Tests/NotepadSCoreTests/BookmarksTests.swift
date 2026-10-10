import XCTest
@testable import NotepadSCore

final class BookmarksTests: XCTestCase {

    func testToggleNextAndPreviousWrapAround() {
        var bookmarks = Bookmarks()
        for line in [3, 10, 7] { bookmarks.toggle(line) }
        XCTAssertEqual(bookmarks.next(after: 3), 7)
        XCTAssertEqual(bookmarks.next(after: 10), 3, "wraps to the first")
        XCTAssertEqual(bookmarks.previous(before: 3), 10, "wraps to the last")
        XCTAssertEqual(bookmarks.previous(before: 8), 7)
        bookmarks.toggle(7)
        XCTAssertEqual(bookmarks.lines, [3, 10])
        XCTAssertNil(Bookmarks().next(after: 0))
    }

    /// Bookmarks move with their lines when lines are inserted or removed above them.
    func testEditsMoveBookmarks() {
        func apply(_ text: String, _ editedRange: NSRange, _ replacement: String, _ marked: Set<Int>) -> Set<Int> {
            let string = NSMutableString(string: text)
            var index = LineIndex(text: string)
            string.replaceCharacters(in: editedRange, with: replacement)
            let changeInLength = (replacement as NSString).length - editedRange.length
            let change = index.applyEditReportingLines(editedRange: NSRange(location: editedRange.location,
                                                                            length: (replacement as NSString).length),
                                                       changeInLength: changeInLength, in: string)
            var bookmarks = Bookmarks(lines: marked)
            bookmarks.apply(change, lineCount: index.lineCount)
            return bookmarks.lines
        }
        let text = "a\nb\nc\nd\ne"
        XCTAssertEqual(apply(text, NSRange(location: 0, length: 0), "new\r\n", [2, 4]), [3, 5], "a line inserted at the top")
        XCTAssertEqual(apply(text, NSRange(location: 2, length: 2), "", [0, 3, 4]), [0, 2, 3], "line b deleted")
        XCTAssertEqual(apply(text, NSRange(location: 2, length: 4), "", [1, 2, 4]), [1, 2], "lines b and c deleted: their marks join")
        XCTAssertEqual(apply(text, NSRange(location: 9, length: 0), "x😀", [4]), [4], "typing on the marked line")
    }
}
