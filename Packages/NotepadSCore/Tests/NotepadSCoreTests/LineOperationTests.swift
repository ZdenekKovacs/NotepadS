import XCTest
@testable import NotepadSCore

/// Join, split, reverse, shuffle and remove lines (Text › Lines).
final class LineOperationTests: XCTestCase {

    private func apply(_ transform: TextTransform, _ text: String, lineEnding: LineEnding = .lf) throws -> String {
        try transform.apply(to: text, context: TransformContext(lineEnding: lineEnding, locale: Locale(identifier: "en_US")))
    }

    // MARK: - Join

    func testJoinPutsOneSpaceBetweenLines() throws {
        XCTAssertEqual(try apply(.joinLines, "a\nb\r\nc\rd"), "a b c d")
    }

    func testJoinDropsTheNextLinesIndentationAndKeepsTheFinalBreak() throws {
        XCTAssertEqual(try apply(.joinLines, "if x {\n    y()\n}\r\n"), "if x { y() }\r\n")
    }

    func testJoinAddsNoSecondSpaceAndSkipsEmptyLines() throws {
        XCTAssertEqual(try apply(.joinLines, "a \nb\n\nc"), "a b c")
    }

    func testJoinNonASCII() throws {
        XCTAssertEqual(try apply(.joinLines, "žluťoučký\n  kůň 😀\n"), "žluťoučký kůň 😀\n")
    }

    func testJoinSingleLineIsUnchanged() throws {
        XCTAssertEqual(try apply(.joinLines, "a b\n"), "a b\n")
        XCTAssertEqual(try apply(.joinLines, ""), "")
    }

    // MARK: - Split

    func testSplitAtSpacesUpToTheWidth() {
        XCTAssertEqual(LineTools.split("one two three four", width: 9, context: .init(lineEnding: .lf)),
                       "one two\nthree\nfour")
    }

    func testSplitUsesTheDocumentsBreakAndKeepsTheLinesOwnBreak() {
        XCTAssertEqual(LineTools.split("aa bb cc\rshort\n", width: 5, context: .init(lineEnding: .crlf)),
                       "aa bb\r\ncc\rshort\n")
    }

    func testSplitKeepsIndentationOnTheFirstPieceAndLongWordsWhole() {
        XCTAssertEqual(LineTools.split("  abcdefgh ij", width: 4, context: .init(lineEnding: .lf)),
                       "  abcdefgh\nij")
    }

    func testSplitCountsCharactersNotUTF16Units() {
        XCTAssertEqual(LineTools.split("😀😀 éé ž", width: 5, context: .init(lineEnding: .lf)), "😀😀 éé\nž")
    }

    func testSplitLeavesShortAndBlankLinesAlone() {
        let text = "short\n          \nx\r\n"
        XCTAssertEqual(LineTools.split(text, width: 5, context: .init(lineEnding: .lf)), text)
    }

    // MARK: - Reverse and shuffle

    func testReverseKeepsEachLinesBreak() throws {
        XCTAssertEqual(try apply(.reverseLines, "a\r\nb\rc\n"), "c\nb\ra\r\n")
        XCTAssertEqual(try apply(.reverseLines, "a\nb"), "b\na", "no final break before or after")
    }

    func testShuffleIsAPermutationKeepingBreaks() {
        var generator = SplitMix64(seed: 42)
        let text = "1\n2\r\n3\r4\n5\n6\n7\n8\n"
        let shuffled = LineTools.shuffle(text, context: .init(lineEnding: .lf), using: &generator)
        XCTAssertNotEqual(shuffled, text, "with this seed the order changes")
        let original = TextLines(text).lines, result = TextLines(shuffled).lines
        XCTAssertEqual(result.map(\.content).sorted(), original.map(\.content).sorted())
        for line in result {
            XCTAssertEqual(line.terminator, original.first { $0.content == line.content }?.terminator)
        }
    }

    // MARK: - Remove

    func testRemoveEmptyLinesIncludingWhitespaceOnly() throws {
        XCTAssertEqual(try apply(.removeEmptyLines, "a\n\n  \t\r\nb\r\n\rc"), "a\nb\r\nc")
    }

    func testRemoveEmptyLinesKeepsTheFinalBreak() throws {
        XCTAssertEqual(try apply(.removeEmptyLines, "a\nb\n\n\n"), "a\nb\n")
        XCTAssertEqual(try apply(.removeEmptyLines, "\n\n"), "")
    }

    func testRemoveConsecutiveDuplicatesKeepsLaterRepeats() throws {
        XCTAssertEqual(try apply(.removeConsecutiveDuplicateLines, "a\na\r\nb\na\nA\né\ne\u{301}"), "a\nb\na\nA\né")
    }

    func testAllLineOperationsAreLineBased() {
        for transform in [TextTransform.joinLines, .reverseLines, .shuffleLines, .removeEmptyLines,
                          .removeConsecutiveDuplicateLines] {
            XCTAssertTrue(transform.isLineBased, transform.rawValue)
        }
    }
}

/// A seeded random number generator, so the shuffle test always gives the same order.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
