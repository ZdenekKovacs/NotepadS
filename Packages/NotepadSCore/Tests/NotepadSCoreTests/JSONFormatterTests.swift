import XCTest
@testable import NotepadSCore

final class JSONFormatterTests: XCTestCase {

    private func format(_ text: String, lineEnding: LineEnding = .lf, indent: String = "  ") throws -> String {
        try TextTransform.formatJSON.apply(to: text, context: TransformContext(lineEnding: lineEnding, indentation: indent))
    }

    private func minify(_ text: String) throws -> String {
        try TextTransform.minifyJSON.apply(to: text, context: TransformContext(lineEnding: .lf))
    }

    private func assertError(_ text: String, line: Int, column: Int,
                             file: StaticString = #filePath, lineNumber: UInt = #line) {
        XCTAssertThrowsError(try format(text), file: file, line: lineNumber) { error in
            guard let error = error as? TransformError else { return XCTFail("\(error)", file: file, line: lineNumber) }
            XCTAssertEqual(error.line, line, "line of \(error.message)", file: file, line: lineNumber)
            XCTAssertEqual(error.column, column, "column of \(error.message)", file: file, line: lineNumber)
        }
    }

    func testFormat() throws {
        XCTAssertEqual(try format(#"{"b":1,"a":[true,null,{"x":"y"}],"e":{},"f":[]}"#), """
        {
          "b": 1,
          "a": [
            true,
            null,
            {
              "x": "y"
            }
          ],
          "e": {},
          "f": []
        }
        """)
    }

    func testKeyOrderAndNumbersAreKeptExactly() throws {
        let input = #"{"z": 1.0, "a": 12345678901234567890123, "m": -0.5e-10, "n": 1E+2}"#
        XCTAssertEqual(try minify(input), #"{"z":1.0,"a":12345678901234567890123,"m":-0.5e-10,"n":1E+2}"#)
    }

    func testStringsAreCopiedUnchanged() throws {
        let input = #"[ "a b\t", "é😀", "\"q\" \\ \/ é", " : , { } [ ] " ]"#
        XCTAssertEqual(try minify(input), #"["a b\t","é😀","\"q\" \\ \/ é"," : , { } [ ] "]"#)
    }

    func testFormatUsesDocumentLineBreaksAndIndentation() throws {
        XCTAssertEqual(try format("[1,2]", lineEnding: .crlf, indent: "\t"), "[\r\n\t1,\r\n\t2\r\n]")
    }

    func testFinalLineBreakIsKept() throws {
        XCTAssertEqual(try format("{}\r\n", lineEnding: .crlf), "{}\r\n")
        XCTAssertEqual(try minify("[1]\n"), "[1]\n")
        XCTAssertEqual(try minify("[1]"), "[1]")
    }

    func testInputWithAnyLineBreaksAndScalarValues() throws {
        XCTAssertEqual(try minify("{\r\n  \"a\" :\r 1 \n}"), #"{"a":1}"#)
        XCTAssertEqual(try format("  42 "), "42")
        XCTAssertEqual(try format(#""text""#), #""text""#)
    }

    func testFormatThenMinifyRoundTrips() throws {
        let minified = #"{"a":[1,{"b":[[],{}]}],"c":"d"}"#
        XCTAssertEqual(try minify(try format(minified)), minified)
    }

    // MARK: - Errors

    func testErrorsReportLineAndColumn() {
        assertError("{\n  \"a\": 1,\n  \"b\" 2\n}", line: 3, column: 7)        // missing colon
        assertError("[1, 2,]", line: 1, column: 7)                           // trailing comma
        assertError("{\"a\": 1} x", line: 1, column: 10)                     // text after the value
        assertError("{'a': 1}", line: 1, column: 2)                          // single quotes
        assertError("[01]", line: 1, column: 3)                              // leading zero
        assertError("[1.]", line: 1, column: 4)
        assertError("[tru]", line: 1, column: 5)
        assertError("\"abc", line: 1, column: 1)                             // never closed
        assertError("[\"a\\x\"]", line: 1, column: 4)                        // bad escape
        assertError("[\"a\nb\"]", line: 1, column: 4)                        // raw line break in a string
        assertError("", line: 1, column: 1)
        assertError("[1\r\n,\r\n", line: 3, column: 1)                       // CRLF counts as one line break
    }

    func testDeepNestingIsRefusedNotCrashing() {
        let deep = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        XCTAssertThrowsError(try minify(deep))
    }

    func testIsNotLineBased() {
        XCTAssertFalse(TextTransform.formatJSON.isLineBased)
        XCTAssertFalse(TextTransform.minifyJSON.isLineBased)
    }
}
