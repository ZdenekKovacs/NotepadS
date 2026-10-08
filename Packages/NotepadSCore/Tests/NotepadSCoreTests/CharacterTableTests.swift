import XCTest
@testable import NotepadSCore

final class CharacterTableTests: XCTestCase {

    private func entry(_ code: Int) -> CharacterTable.Entry? {
        CharacterTable.entries.first { $0.code == code }
    }

    func testAllCodesExceptTheFiveUnusedOnes() {
        XCTAssertEqual(CharacterTable.entries.count, 251)
        for unused in [0x81, 0x8D, 0x8F, 0x90, 0x9D] {
            XCTAssertNil(entry(unused))
        }
        XCTAssertEqual(CharacterTable.entries.map(\.code), CharacterTable.entries.map(\.code).sorted())
    }

    func testASCII() {
        XCTAssertEqual(entry(65)?.character, "A")
        XCTAssertEqual(entry(65)?.hex, "41")
        XCTAssertEqual(entry(65)?.htmlNumber, "&#65;")
        XCTAssertNil(entry(65)?.htmlName)
        XCTAssertEqual(entry(38)?.htmlName, "&amp;")
        XCTAssertEqual(entry(60)?.htmlName, "&lt;")
    }

    func testControlCharacters() {
        XCTAssertEqual(entry(0)?.controlName, "NUL")
        XCTAssertEqual(entry(9)?.controlName, "TAB")
        XCTAssertEqual(entry(13)?.character, "\r")
        XCTAssertEqual(entry(32)?.controlName, "SP")
        XCTAssertEqual(entry(127)?.controlName, "DEL")
        XCTAssertNil(entry(33)?.controlName)
    }

    func testWindows1252RangeUsesUnicodeForHTML() {
        XCTAssertEqual(entry(0x80)?.character, "€")
        XCTAssertEqual(entry(0x80)?.unicode, "U+20AC")
        XCTAssertEqual(entry(0x80)?.htmlName, "&euro;")
        XCTAssertEqual(entry(0x80)?.htmlNumber, "&#8364;")
        XCTAssertEqual(entry(0x9A)?.character, "š")
        XCTAssertEqual(entry(0x9A)?.htmlName, "&scaron;")
        XCTAssertEqual(entry(0x96)?.htmlName, "&ndash;")
    }

    func testLatin1Range() {
        XCTAssertEqual(entry(0xA0)?.controlName, "NBSP")
        XCTAssertEqual(entry(0xA9)?.htmlName, "&copy;")
        XCTAssertEqual(entry(0xE9)?.character, "é")
        XCTAssertEqual(entry(0xE9)?.htmlName, "&eacute;")
        XCTAssertEqual(entry(0xFF)?.htmlName, "&yuml;")
        XCTAssertEqual(entry(0xFF)?.unicode, "U+00FF")
    }
}
