import XCTest
@testable import NotepadSCore

final class TextLinesTests: XCTestCase {

    func testSplitKeepsEveryBreakStyle() {
        let lines = TextLines("a\nb\r\nc\rd")
        XCTAssertEqual(lines.lines, [
            .init(content: "a", terminator: "\n"), .init(content: "b", terminator: "\r\n"),
            .init(content: "c", terminator: "\r"), .init(content: "d", terminator: ""),
        ])
    }

    func testRoundTripIsByteExact() {
        for text in ["", "\n", "\r\n\r\n", "a", "a\n", "é😀\r\nñ\r\rß\n", "\r", "x\r\n"] {
            XCTAssertEqual(TextLines(text).text, text, String(reflecting: text))
        }
    }

    func testTextEndingWithBreakHasNoExtraEmptyLine() {
        XCTAssertEqual(TextLines("a\nb\n").lines.count, 2)
        XCTAssertEqual(TextLines("a\n\n").lines.count, 2, "an empty line is still a line")
    }
}

final class LineToolsTests: XCTestCase {

    private let english = TransformContext(lineEnding: .lf, locale: Locale(identifier: "en_US"))

    private func apply(_ transform: TextTransform, _ text: String, lineEnding: LineEnding = .lf) throws -> String {
        try transform.apply(to: text, context: TransformContext(lineEnding: lineEnding, locale: english.locale))
    }

    // MARK: - Sort

    /// Accented letters sort right after their base letter ("Eclair", "éclair"), not after "z".
    func testSortIsLocaleAwareCaseInsensitiveAndNumeric() throws {
        XCTAssertEqual(try apply(.sortLinesAscending, "file10\nZebra\néclair\nfile2\napple\nEclair\n"),
                       "apple\nEclair\néclair\nfile2\nfile10\nZebra\n")
        XCTAssertEqual(try apply(.sortLinesDescending, "b\na\nc"), "c\nb\na")
    }

    func testSortIsStable() throws {
        XCTAssertEqual(try apply(.sortLinesAscending, "B\nb\nA\n"), "A\nB\nb\n")
    }

    func testSortKeepsEachLinesBreak() throws {
        // "c" keeps its CRLF, "a" its CR; only the last line moved and needs a new break.
        XCTAssertEqual(try apply(.sortLinesAscending, "c\r\nb\na\rz", lineEnding: .crlf), "a\rb\nc\r\nz")
        XCTAssertEqual(try apply(.sortLinesAscending, "c\r\nb", lineEnding: .crlf), "b\r\nc",
                       "the last line gets the document style, and the text still doesn't end with a break")
    }

    func testSortEmptyAndSingleLine() throws {
        XCTAssertEqual(try apply(.sortLinesAscending, ""), "")
        XCTAssertEqual(try apply(.sortLinesAscending, "only"), "only")
    }

    // MARK: - Remove duplicates

    func testRemoveDuplicatesKeepsFirstOccurrence() throws {
        XCTAssertEqual(try apply(.removeDuplicateLines, "b\na\nb\nc\na\n"), "b\na\nc\n")
    }

    func testDuplicatesIgnoreBreakStyleButAreCaseSensitive() throws {
        // "X" ends up last; the text didn't end with a break, so neither does the result.
        XCTAssertEqual(try apply(.removeDuplicateLines, "x\r\nx\nX\rx"), "x\r\nX")
        XCTAssertEqual(try apply(.removeDuplicateLines, "é\ne\u{301}\n"), "é\n",
                       "the same letter written two ways in Unicode counts as the same line")
    }

    // MARK: - Trim

    func testTrimTrailingWhitespace() throws {
        XCTAssertEqual(try apply(.trimTrailingWhitespace, "a  \nb\t\t\r\n  c \u{00A0}\r d"), "a\nb\r\n  c\r d")
    }

    func testTrimNeverTouchesLineBreaks() throws {
        let text = "x \r\n\r\n \r\n"
        XCTAssertEqual(try apply(.trimTrailingWhitespace, text), "x\r\n\r\n\r\n")
        XCTAssertEqual(try apply(.trimTrailingWhitespace, "é😀  "), "é😀")
    }

    func testAllLineToolsAreLineBased() {
        for transform in [TextTransform.sortLinesAscending, .sortLinesDescending, .removeDuplicateLines, .trimTrailingWhitespace] {
            XCTAssertTrue(transform.isLineBased)
        }
    }
}
