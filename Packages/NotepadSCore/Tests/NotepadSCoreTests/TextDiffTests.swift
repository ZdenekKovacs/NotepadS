import XCTest
@testable import NotepadSCore

final class TextDiffTests: XCTestCase {

    /// Rows as "kind left→right" with 1-based lines and "-" for a gap.
    private func rows(_ left: String, _ right: String, _ options: TextDiff.Options = .init()) -> [String] {
        let diff = TextDiff(left: TextLines(left).lines.map(\.content), right: TextLines(right).lines.map(\.content),
                            options: options)
        return diff.rows.map { row in
            let l = row.leftLine.map { String($0 + 1) } ?? "-"
            let r = row.rightLine.map { String($0 + 1) } ?? "-"
            return "\(row.kind) \(l)→\(r)"
        }
    }

    func testIdenticalTextsIgnoringLineBreakStyles() {
        let diff = TextDiff(left: TextLines("a\r\nb\r\n").lines.map(\.content), right: TextLines("a\nb\n").lines.map(\.content))
        XCTAssertTrue(diff.isIdentical)
        XCTAssertEqual(diff.differenceStarts, [])
    }

    func testAddedRemovedAndChangedLines() {
        XCTAssertEqual(rows("a\nb\nc\nd", "a\nc\nd\ne"), ["same 1→1", "removed 2→-", "same 3→2", "same 4→3", "added -→4"])
        XCTAssertEqual(rows("a\nold line\nz", "a\nnew line\nz"), ["same 1→1", "changed 2→2", "same 3→3"])
        XCTAssertEqual(rows("a\nx\ny\nz", "a\nq\nz"), ["same 1→1", "removed 2→-", "removed 3→-", "added -→2", "same 4→3"],
                       "nothing alike: shown as removed and added, not as changed")
    }

    func testEmptyTexts() {
        XCTAssertEqual(rows("", "a\nb"), ["added -→1", "added -→2"])
        XCTAssertEqual(rows("a", ""), ["removed 1→-"])
        XCTAssertEqual(rows("", ""), [])
    }

    func testSimilarLinesArePairedEvenIfNotFirst() {
        let left = "let count = 3\nfor i in 0..<count {\n    greet(name: \"user\")"
        let right = "for i in 0..<5 {\n    greet(name: \"user\", loud: true)"
        XCTAssertEqual(rows(left, right), ["removed 1→-", "changed 2→1", "changed 3→2"])
    }

    func testOptions() {
        XCTAssertEqual(rows("a  b\nC", "a b \nc", .init(ignoresWhitespace: true, ignoresCase: true)), ["same 1→1", "same 2→2"])
        XCTAssertEqual(rows("a  b", "a b"), ["changed 1→1"])
    }

    func testDifferenceStartsAndCounts() {
        let diff = TextDiff(left: ["a", "bb", "c", "d", "ee"], right: ["a", "bbx", "c", "d", "eex", "f"])
        XCTAssertEqual(diff.differenceStarts, [1, 4])
        XCTAssertEqual(diff.counts.changed, 2)
        XCTAssertEqual(diff.counts.added, 1)
        XCTAssertEqual(diff.counts.removed, 0)
    }

    func testFindsTheShortestEditOnShuffledLines() {
        let left = ["1", "2", "3", "4", "5", "6", "7", "8"]
        let right = ["1", "3", "2", "4", "6", "5", "7", "9", "8"]
        let diff = TextDiff(left: left, right: right)
        // Every left and right line appears exactly once, in order.
        XCTAssertEqual(diff.rows.compactMap(\.leftLine), Array(0..<left.count))
        XCTAssertEqual(diff.rows.compactMap(\.rightLine), Array(0..<right.count))
        XCTAssertEqual(diff.rows.filter { $0.kind == .same }.count, 6, "1, 2 or 3, 4, 5 or 6, 7, 8 stay")
    }

    func testLargeFilesWithFewChanges() {
        let left = (0..<20_000).map { "line \($0)" }
        var right = left
        right[10_000] = "changed"
        right.insert("new", at: 15_000)
        let start = Date()
        let diff = TextDiff(left: left, right: right)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(diff.differenceStarts.count, 2)
    }

    func testCompletelyDifferentTextsBeyondTheLimit() {
        let left = (0..<3_000).map { "a\($0)" }, right = (0..<3_000).map { "b\($0)" }
        let diff = TextDiff(left: left, right: right)
        XCTAssertEqual(diff.counts.changed, 3_000, "too large to align by similarity: paired in order")
    }

    // MARK: - Within a line

    func testChangedRangesWithinALine() {
        let (left, right) = TextDiff.changedRanges(left: "let value = 42", right: "let total = 43")
        // "value" and "total" share "al": only the rest is marked.
        XCTAssertEqual(left.map { ("let value = 42" as NSString).substring(with: $0) }, ["v", "ue", "2"])
        XCTAssertEqual(right.map { ("let total = 43" as NSString).substring(with: $0) }, ["tot", "3"])
    }

    func testChangedRangesCountEmojiAndAccentsAsOneCharacter() {
        let (left, right) = TextDiff.changedRanges(left: "a😀b", right: "aéb")
        XCTAssertEqual(left, [NSRange(location: 1, length: 2)])
        XCTAssertEqual(right, [NSRange(location: 1, length: 1)])
    }

    // MARK: - Side by side

    func testSideBySideAddsFillerRows() {
        let left = ["a", "gone", "c"], right = ["a", "c", "new"]
        let view = TextDiff(left: left, right: right).sideBySide(left: left, right: right)
        XCTAssertEqual(view.left.lines, ["a", "gone", "c", ""])
        XCTAssertEqual(view.right.lines, ["a", "", "c", "new"])
        XCTAssertEqual(view.left.lineNumbers, [1, 2, 3, nil])
        XCTAssertEqual(view.right.lineNumbers, [1, nil, 2, 3])
        XCTAssertEqual(view.kinds, [.same, .removed, .same, .added])
    }
}
