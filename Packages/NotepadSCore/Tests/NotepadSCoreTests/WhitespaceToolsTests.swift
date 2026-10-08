import XCTest
@testable import NotepadSCore

/// Text › Whitespace: trimming, tabs ↔ spaces, line breaks → spaces.
final class WhitespaceToolsTests: XCTestCase {

    private func apply(_ transform: TextTransform, _ text: String, tabWidth: Int = 4) throws -> String {
        try transform.apply(to: text, context: TransformContext(lineEnding: .lf, tabWidth: tabWidth))
    }

    // MARK: - Trim

    func testTrimLeadingKeepsEveryBreakStyle() throws {
        XCTAssertEqual(try apply(.trimLeadingWhitespace, "  \t a \r\n\tb\r  c\n"), "a \r\nb\rc\n")
    }

    func testTrimBothSides() throws {
        XCTAssertEqual(try apply(.trimWhitespace, "  a  \r\n\t b\t\r \u{A0}é😀 \n"), "a\r\nb\ré😀\n")
    }

    func testTrimMakesWhitespaceOnlyLinesEmptyButKeepsThem() throws {
        XCTAssertEqual(try apply(.trimWhitespace, "a\n   \r\nb"), "a\n\r\nb")
    }

    // MARK: - Tabs to spaces

    func testTabsToSpacesFollowsTabStops() throws {
        XCTAssertEqual(try apply(.tabsToSpaces, "a\tb"), "a   b")
        XCTAssertEqual(try apply(.tabsToSpaces, "\t\tx"), "        x")
        XCTAssertEqual(try apply(.tabsToSpaces, "abcd\tx"), "abcd    x", "a tab right at a tab stop is a full tab")
        XCTAssertEqual(try apply(.tabsToSpaces, "a\tb", tabWidth: 8), "a       b")
    }

    func testTabsToSpacesCountsCharactersAndRestartsOnEveryLine() throws {
        XCTAssertEqual(try apply(.tabsToSpaces, "😀é\tx\r\n\ty\rz"), "😀é  x\r\n    y\rz")
    }

    // MARK: - Leading spaces to tabs

    func testLeadingSpacesToTabs() throws {
        XCTAssertEqual(try apply(.leadingSpacesToTabs, "        x"), "\t\tx")
        XCTAssertEqual(try apply(.leadingSpacesToTabs, "      x"), "\t  x", "the rest of a tab stop stays spaces")
        XCTAssertEqual(try apply(.leadingSpacesToTabs, "  \t  x"), "\t  x", "mixed indentation")
    }

    func testLeadingSpacesToTabsLeavesSpacesInsideTheLine() throws {
        XCTAssertEqual(try apply(.leadingSpacesToTabs, "    a    b\r\n    \r\nc"), "\ta    b\r\n\t\r\nc")
    }

    // MARK: - Line breaks to spaces

    func testLineBreaksToSpacesKeepsTheFinalBreak() throws {
        XCTAssertEqual(try apply(.lineBreaksToSpaces, "a\r\nb\rc\n"), "a b c\n")
        XCTAssertEqual(try apply(.lineBreaksToSpaces, "a\n\n  b"), "a    b", "every break becomes one space; nothing trimmed")
        XCTAssertEqual(try apply(.lineBreaksToSpaces, "žluť\n😀"), "žluť 😀")
        XCTAssertEqual(try apply(.lineBreaksToSpaces, ""), "")
    }

    func testAllWhitespaceToolsAreLineBased() {
        for transform in [TextTransform.trimLeadingWhitespace, .trimWhitespace, .tabsToSpaces,
                          .leadingSpacesToTabs, .lineBreaksToSpaces] {
            XCTAssertTrue(transform.isLineBased, transform.rawValue)
        }
    }
}
