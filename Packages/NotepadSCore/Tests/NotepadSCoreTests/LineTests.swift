import XCTest
@testable import NotepadSCore

final class LineEndingTests: XCTestCase {

    func testCountsEachStyle() {
        let counts = LineEnding.count(in: "a\nb\r\nc\rd\r\n")
        XCTAssertEqual(counts, LineEndingCounts(lf: 1, crlf: 2, cr: 1))
        XCTAssertEqual(counts.dominant, .crlf)
        XCTAssertTrue(counts.isMixed)
    }

    func testCountsTrailingCRAndConsecutiveCRs() {
        XCTAssertEqual(LineEnding.count(in: "a\r\r\n\r"), LineEndingCounts(lf: 0, crlf: 1, cr: 2))
    }

    func testNoBreaks() {
        let counts = LineEnding.count(in: "Příliš žluťoučký kůň 😀")
        XCTAssertEqual(counts.total, 0)
        XCTAssertNil(counts.dominant)
        XCTAssertFalse(counts.isMixed)
    }

    func testDominantTiePrefersLF() {
        XCTAssertEqual(LineEndingCounts(lf: 2, crlf: 2, cr: 2).dominant, .lf)
        XCTAssertEqual(LineEndingCounts(lf: 0, crlf: 1, cr: 1).dominant, .crlf)
    }

    func testNormalizeToLF() {
        XCTAssertEqual(LineEnding.normalizeToLF("a\r\nb\rc\nd\r\r\n"), "a\nb\nc\nd\n\n")
        XCTAssertEqual(LineEnding.normalizeToLF("ř\n😀"), "ř\n😀")
    }

    func testConvertAll() {
        let mixed = "ř\r\nž\rš\n"
        XCTAssertEqual(LineEnding.convertAll(mixed, to: .lf), "ř\nž\nš\n")
        XCTAssertEqual(LineEnding.convertAll(mixed, to: .crlf), "ř\r\nž\r\nš\r\n")
        XCTAssertEqual(LineEnding.convertAll(mixed, to: .cr), "ř\rž\rš\r")
        // Converting twice must not double "\r\n" into "\r\r\n".
        XCTAssertEqual(LineEnding.convertAll(LineEnding.convertAll(mixed, to: .crlf), to: .crlf), "ř\r\nž\r\nš\r\n")
    }
}

final class LineIndexTests: XCTestCase {

    func testEmptyText() {
        let index = LineIndex(text: "")
        XCTAssertEqual(index.lineCount, 1)
        XCTAssertEqual(index.contentRange(ofLine: 0), NSRange(location: 0, length: 0))
        XCTAssertEqual(index.line(containing: 0), 0)
    }

    func testMixedBreaks() {
        //            0123 4 5 67 8 9
        let text = "ab\r\ncd\ref\n" as NSString
        let index = LineIndex(text: text)
        XCTAssertEqual(index.lineStarts, [0, 4, 7, 10])
        XCTAssertEqual(index.breakStyles, [.crlf, .cr, .lf])
        XCTAssertEqual(index.counts, LineEndingCounts(lf: 1, crlf: 1, cr: 1))
        XCTAssertEqual(index.contentRange(ofLine: 0), NSRange(location: 0, length: 2))
        XCTAssertEqual(index.contentRange(ofLine: 1), NSRange(location: 4, length: 2))
        XCTAssertEqual(index.contentRange(ofLine: 2), NSRange(location: 7, length: 2))
        XCTAssertEqual(index.contentRange(ofLine: 3), NSRange(location: 10, length: 0))
        XCTAssertEqual(index.fullRange(ofLine: 0), NSRange(location: 0, length: 4))
        XCTAssertEqual(index.line(containing: 2), 0)   // right before "\r\n"
        XCTAssertEqual(index.line(containing: 3), 0)   // between "\r" and "\n"
        XCTAssertEqual(index.line(containing: 4), 1)
        XCTAssertEqual(index.line(containing: 10), 3)
    }

    func testCROnlyFile() {
        let index = LineIndex(text: "a\rb\rc")
        XCTAssertEqual(index.lineStarts, [0, 2, 4])
        XCTAssertEqual(index.counts.dominant, .cr)
        XCTAssertFalse(index.counts.isMixed)
    }

    func testColumnCountsCharacters() {
        let text = "ř😀\tx\r\nžluť" as NSString
        let index = LineIndex(text: text)
        // "ř" (1 unit), "😀" (2 units), "\t", "x" → offset 5 is after "x".
        XCTAssertEqual(index.column(of: 0, in: text), 1)
        XCTAssertEqual(index.column(of: 1, in: text), 2)
        XCTAssertEqual(index.column(of: 3, in: text), 3)
        XCTAssertEqual(index.column(of: 5, in: text), 5)
        XCTAssertEqual(index.column(of: 6, in: text), 5)   // between "\r" and "\n"
        XCTAssertEqual(index.column(of: 7, in: text), 1)
        XCTAssertEqual(index.column(of: 11, in: text), 5)
    }

    func testColumnOnLongLineUsesUTF16Units() {
        let text = String(repeating: "😀", count: 20) as NSString
        let index = LineIndex(text: text)
        XCTAssertEqual(index.column(of: 40, in: text, longLineThreshold: 10), 41)
        XCTAssertEqual(index.column(of: 40, in: text), 21)
    }

    // MARK: - Incremental updates

    func testInsertLFAfterCRJoinsIntoCRLF() {
        assertEdit(from: "a\rb", replacing: NSRange(location: 2, length: 0), with: "\n")
    }

    func testDeleteBetweenCRAndLFJoinsThem() {
        assertEdit(from: "a\rX\nb", replacing: NSRange(location: 2, length: 1), with: "")
    }

    func testInsertBetweenCRAndLFSplitsThem() {
        assertEdit(from: "a\r\nb", replacing: NSRange(location: 2, length: 0), with: "X")
    }

    func testDeleteHalfOfCRLF() {
        assertEdit(from: "a\r\nb\nc", replacing: NSRange(location: 1, length: 1), with: "")
        assertEdit(from: "a\r\nb\nc", replacing: NSRange(location: 2, length: 1), with: "")
    }

    func testInsertCRBeforeLF() {
        assertEdit(from: "a\nb\nc", replacing: NSRange(location: 1, length: 0), with: "\r")
        assertEdit(from: "a\nb\nc", replacing: NSRange(location: 1, length: 0), with: "x\r")
    }

    func testReplaceEverything() {
        assertEdit(from: "a\r\nb\rc\n", replacing: NSRange(location: 0, length: 7), with: "ř\n😀\r\n")
    }

    /// Thousands of random edits with line breaks of every style, each compared with a full
    /// rebuild (line starts, break styles and counts).
    func testRandomEditsMatchRebuild() {
        var generator = SeededGenerator(seed: 1250)
        let pieces = ["a", "ř", "😀", "\r", "\n", "\r\n", " ", "ž"]
        let text = NSMutableString()
        var index = LineIndex(text: text)

        for step in 0..<20_000 {
            let location = Int.random(in: 0...text.length, using: &generator)
            let maxDelete = min(text.length - location, 6)
            let deleteLength = Int.random(in: 0...maxDelete, using: &generator)
            var insertion = ""
            for _ in 0..<Int.random(in: 0...4, using: &generator) {
                insertion += pieces.randomElement(using: &generator)!   // non-empty array
            }
            let range = NSRange(location: location, length: deleteLength)
            text.replaceCharacters(in: range, with: insertion)
            let insertedLength = (insertion as NSString).length
            index.applyEdit(editedRange: NSRange(location: location, length: insertedLength),
                            changeInLength: insertedLength - deleteLength,
                            in: text)

            let expected = LineIndex(text: text)
            if index != expected {
                XCTFail("Mismatch after step \(step): text \(String(reflecting: text as String))")
                return
            }
            // Keep the text short so edits often touch line breaks.
            if text.length > 200 {
                text.setString("")
                index = LineIndex(text: text)
            }
        }
    }

    private func assertEdit(from original: String, replacing range: NSRange, with insertion: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let text = NSMutableString(string: original)
        var index = LineIndex(text: text)
        text.replaceCharacters(in: range, with: insertion)
        let insertedLength = (insertion as NSString).length
        index.applyEdit(editedRange: NSRange(location: range.location, length: insertedLength),
                        changeInLength: insertedLength - range.length,
                        in: text)
        XCTAssertEqual(index, LineIndex(text: text), file: file, line: line)
    }
}

/// Deterministic random numbers, so a failing random test fails the same way every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
