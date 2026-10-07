import XCTest
@testable import NotepadSCore

final class TextStatisticsTests: XCTestCase {

    private func count(_ text: String) -> Int {
        let string = text as NSString
        return TextStatistics.characterCount(of: string, in: NSRange(location: 0, length: string.length))
    }

    func testEmptyText() {
        XCTAssertEqual(count(""), 0)
    }

    func testPlainASCII() {
        XCTAssertEqual(count("hello"), 5)
    }

    /// CRLF is one user-perceived character, like Swift's `Character`; LF and CR are one each.
    func testLineBreaksOfEveryStyle() {
        XCTAssertEqual(count("a\nb"), 3)
        XCTAssertEqual(count("a\r\nb"), 3)
        XCTAssertEqual(count("a\rb"), 3)
        XCTAssertEqual(count("a\n\r\nb\r"), 5, "mixed: LF, CRLF, CR")
        XCTAssertEqual(count("\r\r\n"), 2, "a lone CR before a CRLF")
    }

    func testAccentedLettersPrecomposedAndDecomposed() {
        XCTAssertEqual(count("café"), 4)
        XCTAssertEqual(count("cafe\u{301}"), 4, "e + combining acute accent is one character")
        XCTAssertEqual(count("Žluťoučký"), 9)
    }

    func testEmojiAreOneCharacterEach() {
        XCTAssertEqual(count("😀"), 1, "a surrogate pair")
        XCTAssertEqual(count("👨‍👩‍👧"), 1, "a ZWJ sequence")
        XCTAssertEqual(count("🇨🇿"), 1, "a flag")
        XCTAssertEqual(count("👍🏽"), 1, "skin-tone modifier")
        XCTAssertEqual(count("a😀\r\nb"), 4)
    }

    func testMatchesSwiftCharacterCount() {
        for text in ["", "a\r\nb\rc\n", "é😀\r\nñ\r\rß\n", "\t  x\u{301}\u{302}🇨🇿🇩🇪"] {
            XCTAssertEqual(count(text), text.count, String(reflecting: text))
        }
    }

    func testCountsOnlyTheGivenRange() {
        let text = "ab😀cd" as NSString   // 😀 is two UTF-16 units: a b [😀] c d = 6 units
        XCTAssertEqual(TextStatistics.characterCount(of: text, in: NSRange(location: 1, length: 3)), 2)   // b 😀
        XCTAssertEqual(TextStatistics.characterCount(of: text, in: NSRange(location: 4, length: 2)), 2)   // c d
    }

    func testInvalidRangeCountsNothing() {
        let text = "abc" as NSString
        XCTAssertEqual(TextStatistics.characterCount(of: text, in: NSRange(location: 2, length: 5)), 0)
        XCTAssertEqual(TextStatistics.characterCount(of: text, in: NSRange(location: NSNotFound, length: 0)), 0)
    }

    func testLargeTextIsCountedQuickly() {
        let line = "Příliš žluťoučký kůň úpěl ďábelské ódy 😀\r\n"   // 41 characters
        let text = String(repeating: line, count: 20_000) as NSString   // about 0.9 million UTF-16 units
        let start = Date()
        XCTAssertEqual(TextStatistics.characterCount(of: text, in: NSRange(location: 0, length: text.length)), 41 * 20_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "debug builds are slower; a release build counts this in a fraction of that")
    }
}
