import XCTest
@testable import NotepadSCore

final class TextSearchTests: XCTestCase {

    private let regex = SearchOptions(isRegularExpression: true)

    private func texts(_ ranges: [NSRange], in text: NSString) -> [String] {
        ranges.map { text.substring(with: $0) }
    }

    func testPlainTextSearchTreatsSpecialCharactersLiterally() throws {
        let text = "a.b axb a.b" as NSString
        let search = try TextSearch(pattern: "a.b", options: SearchOptions())
        XCTAssertEqual(search.matches(in: text).count, 2)
    }

    func testIgnoreCaseAndUnicode() throws {
        let text = "Café CAFÉ café 😀 café" as NSString
        XCTAssertEqual(try TextSearch(pattern: "café", options: SearchOptions()).matches(in: text).count, 2)
        let ignoring = try TextSearch(pattern: "café", options: SearchOptions(ignoresCase: true))
        XCTAssertEqual(ignoring.matches(in: text).count, 4)
        XCTAssertEqual(ignoring.matches(in: text).last, NSRange(location: 18, length: 4), "UTF-16 offsets after the emoji")
    }

    func testAnchorsMatchEveryLineWithAnyBreakStyle() throws {
        let text = "one\r\ntwo\rthree\nfour" as NSString
        let search = try TextSearch(pattern: "^\\w+$", options: regex)
        XCTAssertEqual(texts(search.matches(in: text), in: text), ["one", "two", "three", "four"])
    }

    func testReplaceAllWithGroups() throws {
        let text = "ann@example bob@test" as NSString
        let search = try TextSearch(pattern: "(\\w+)@(\\w+)", options: regex)
        let result = search.replaceAll(in: text, range: NSRange(location: 0, length: text.length),
                                       template: "$2: $1", lineEnding: .lf)
        XCTAssertEqual(result.text, "example: ann test: bob")
        XCTAssertEqual(result.count, 2)
    }

    func testNewlineInReplacementUsesTheDocumentStyle() throws {
        let text = "a,b,c" as NSString
        let search = try TextSearch(pattern: ",", options: regex)
        XCTAssertEqual(search.replaceAll(in: text, range: NSRange(location: 0, length: 5), template: "\\n",
                                         lineEnding: .crlf).text, "a\r\nb\r\nc")
        XCTAssertEqual(search.replaceAll(in: text, range: NSRange(location: 0, length: 5), template: "\\t\\\\$",
                                         lineEnding: .lf).text, "a\t\\$b\t\\$c", "\\\\ is a backslash, \\$ a dollar")
    }

    func testPlainTextReplacementIsLiteral() throws {
        let text = "x" as NSString
        let search = try TextSearch(pattern: "x", options: SearchOptions())
        XCTAssertEqual(search.replaceAll(in: text, range: NSRange(location: 0, length: 1), template: "$1 \\n",
                                         lineEnding: .lf).text, "$1 \\n")
    }

    func testReplaceOneMatch() throws {
        let text = "id=42; id=7" as NSString
        let search = try TextSearch(pattern: "id=(\\d+)", options: regex)
        let second = try XCTUnwrap(search.matches(in: text).last)
        XCTAssertEqual(search.replacement(for: second, in: text, template: "#$1", lineEnding: .lf), "#7")
    }

    func testNextAndPreviousWrapAround() throws {
        let text = "x..x..x" as NSString
        let search = try TextSearch(pattern: "x", options: SearchOptions())
        XCTAssertEqual(search.nextMatch(in: text, from: 1, wraps: true)?.location, 3)
        XCTAssertEqual(search.nextMatch(in: text, from: 7, wraps: true)?.location, 0)
        XCTAssertNil(search.nextMatch(in: text, from: 7, wraps: false))
        XCTAssertEqual(search.previousMatch(in: text, before: 3, wraps: true)?.location, 0)
        XCTAssertEqual(search.previousMatch(in: text, before: 0, wraps: true)?.location, 6)
    }

    func testEmptyMatchesDontStickInPlace() throws {
        let text = "ab\ncd" as NSString
        let search = try TextSearch(pattern: "^", options: regex)
        XCTAssertEqual(search.nextMatch(in: text, from: 0, wraps: false)?.location, 3)
    }

    func testInvalidPatterns() {
        XCTAssertThrowsError(try TextSearch(pattern: "", options: SearchOptions()))
        XCTAssertThrowsError(try TextSearch(pattern: "(unclosed", options: regex))
        XCTAssertNoThrow(try TextSearch(pattern: "(unclosed", options: SearchOptions()), "plain text can't be invalid")
    }
}
