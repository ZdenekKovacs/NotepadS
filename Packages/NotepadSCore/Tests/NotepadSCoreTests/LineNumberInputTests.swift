import XCTest
@testable import NotepadSCore

final class LineNumberInputTests: XCTestCase {

    func testValidNumbers() {
        XCTAssertEqual(LineNumberInput.line(from: "1", lineCount: 10), 0)
        XCTAssertEqual(LineNumberInput.line(from: "10", lineCount: 10), 9)
        XCTAssertEqual(LineNumberInput.line(from: "  7 \n", lineCount: 10), 6)
        XCTAssertEqual(LineNumberInput.line(from: "007", lineCount: 10), 6)
    }

    func testInvalidInput() {
        for input in ["", " ", "0", "11", "-1", "+5", "3.5", "abc", "5a", "1 2", "٣", "99999999999999999999"] {
            XCTAssertNil(LineNumberInput.line(from: input, lineCount: 10), input)
        }
    }

    func testEmptyDocumentHasLineOne() {
        XCTAssertEqual(LineNumberInput.line(from: "1", lineCount: 1), 0)
        XCTAssertNil(LineNumberInput.line(from: "2", lineCount: 1))
    }

    func testNumberForSplitLinesWidth() {
        XCTAssertEqual(LineNumberInput.number(from: " 80 ", maximum: 10_000), 80)
        XCTAssertNil(LineNumberInput.number(from: "0", maximum: 10_000))
        XCTAssertNil(LineNumberInput.number(from: "10001", maximum: 10_000))
    }
}
