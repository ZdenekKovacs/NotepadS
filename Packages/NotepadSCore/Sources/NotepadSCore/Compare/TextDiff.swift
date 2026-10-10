import Foundation

/// The differences between two texts, line by line, for File › Compare With.
///
/// Lines are compared by their text; line-break styles don't count (a file saved with CRLF
/// equals the same file with LF). The result is a list of rows for showing the two texts
/// side by side: equal lines, lines only on the left (removed), only on the right (added),
/// or a left and a right line that differ (changed).
public struct TextDiff: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        case same, removed, added, changed
    }

    /// One row of the side-by-side view. Lines are 0-based; nil where that side has no line
    /// (a gap opposite an added or removed line).
    public struct Row: Equatable, Sendable {
        public let kind: Kind
        public let leftLine: Int?
        public let rightLine: Int?
    }

    public struct Options: Equatable, Sendable {
        /// Spaces and tabs don't count: "a  b " equals "a b".
        public var ignoresWhitespace: Bool
        public var ignoresCase: Bool

        public init(ignoresWhitespace: Bool = false, ignoresCase: Bool = false) {
            self.ignoresWhitespace = ignoresWhitespace
            self.ignoresCase = ignoresCase
        }
    }

    public let rows: [Row]

    /// The row where each block of differences starts, for "Next Difference".
    public var differenceStarts: [Int] {
        var starts: [Int] = []
        for (index, row) in rows.enumerated() where row.kind != .same {
            if index == 0 || rows[index - 1].kind == .same {
                starts.append(index)
            }
        }
        return starts
    }

    public var isIdentical: Bool { rows.allSatisfy { $0.kind == .same } }

    /// Counts for the summary line: lines only on the left, only on the right, and changed pairs.
    public var counts: (removed: Int, added: Int, changed: Int) {
        rows.reduce(into: (0, 0, 0)) { counts, row in
            switch row.kind {
            case .removed: counts.0 += 1
            case .added: counts.1 += 1
            case .changed: counts.2 += 1
            case .same: break
            }
        }
    }

    /// Compares two lists of lines (contents without their breaks, e.g. from `TextLines`).
    public init(left: [String], right: [String], options: Options = Options()) {
        // Compare numbers instead of strings: each distinct (normalized) line gets an ID.
        var ids: [String: Int] = [:]
        func id(_ line: String) -> Int {
            var key = line
            if options.ignoresWhitespace {
                key = key.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            }
            if options.ignoresCase {
                key = key.lowercased()
            }
            if let existing = ids[key] { return existing }
            ids[key] = ids.count
            return ids.count - 1
        }
        let leftIDs = left.map(id), rightIDs = right.map(id)

        var rows: [Row] = []
        var removed: [Int] = [], added: [Int] = []
        // A run of removed and added lines between equal lines: similar lines are paired up as
        // changed lines (shown side by side), the rest stay removed or added.
        func flush() {
            rows += Self.pairedRows(removed: removed, added: added, left: left, right: right)
            removed = []
            added = []
        }
        for edit in Diff.edits(from: leftIDs, to: rightIDs) {
            switch edit {
            case .same(let leftIndex, let rightIndex):
                flush()
                rows.append(Row(kind: .same, leftLine: leftIndex, rightLine: rightIndex))
            case .delete(let leftIndex):
                removed.append(leftIndex)
            case .insert(let rightIndex):
                added.append(rightIndex)
            }
        }
        flush()
        self.rows = rows
    }

    /// Lines this similar (0…1, see `similarity`) are shown as one changed line.
    static let minimumSimilarity = 0.4

    /// Rows for a block of removed and added lines. Pairs lines so that the total similarity
    /// is highest while keeping both sides in order (dynamic programming, like aligning two
    /// sequences), so "let count = 3" doesn't get paired with an unrelated "for" line just
    /// because both come first. Very large blocks are paired in order instead.
    static func pairedRows(removed: [Int], added: [Int], left: [String], right: [String]) -> [Row] {
        let r = removed.count, a = added.count
        guard r > 0, a > 0 else {
            return removed.map { Row(kind: .removed, leftLine: $0, rightLine: nil) }
                + added.map { Row(kind: .added, leftLine: nil, rightLine: $0) }
        }
        guard r * a <= 40_000 else {
            let pairs = min(r, a)
            return (0..<pairs).map { Row(kind: .changed, leftLine: removed[$0], rightLine: added[$0]) }
                + removed.dropFirst(pairs).map { Row(kind: .removed, leftLine: $0, rightLine: nil) }
                + added.dropFirst(pairs).map { Row(kind: .added, leftLine: nil, rightLine: $0) }
        }
        let leftBigrams = removed.map { bigrams(left[$0]) }, rightBigrams = added.map { bigrams(right[$0]) }
        // score[i][j]: best total similarity pairing the first i removed with the first j added lines.
        var score = [[Double]](repeating: [Double](repeating: 0, count: a + 1), count: r + 1)
        var similarity = [[Double]](repeating: [Double](repeating: 0, count: a), count: r)
        for i in 1...r {
            for j in 1...a {
                let value = Self.similarity(leftBigrams[i - 1], rightBigrams[j - 1],
                                            left[removed[i - 1]], right[added[j - 1]])
                similarity[i - 1][j - 1] = value
                let pair = value >= minimumSimilarity ? score[i - 1][j - 1] + value : -1
                score[i][j] = max(score[i - 1][j], score[i][j - 1], pair)
            }
        }
        // Walk back, collecting rows from the end.
        var rows: [Row] = []
        var i = r, j = a
        while i > 0 || j > 0 {
            if i > 0, j > 0, similarity[i - 1][j - 1] >= minimumSimilarity,
               score[i][j] == score[i - 1][j - 1] + similarity[i - 1][j - 1] {
                rows.append(Row(kind: .changed, leftLine: removed[i - 1], rightLine: added[j - 1]))
                i -= 1; j -= 1
            } else if j > 0, i == 0 || score[i][j] == score[i][j - 1] {
                rows.append(Row(kind: .added, leftLine: nil, rightLine: added[j - 1]))
                j -= 1
            } else {
                rows.append(Row(kind: .removed, leftLine: removed[i - 1], rightLine: nil))
                i -= 1
            }
        }
        return rows.reversed()
    }

    /// Character pairs of a line, counted, ignoring leading and trailing spaces.
    private static func bigrams(_ line: String) -> [String: Int] {
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        var counts: [String: Int] = [:]
        guard characters.count > 1 else { return counts }
        for index in 0..<(characters.count - 1) {
            counts[String(characters[index]) + String(characters[index + 1]), default: 0] += 1
        }
        return counts
    }

    /// How alike two lines are, 0 (nothing in common) to 1 (same): the Dice coefficient of
    /// their character pairs.
    private static func similarity(_ first: [String: Int], _ second: [String: Int], _ firstLine: String, _ secondLine: String) -> Double {
        let total = first.values.reduce(0, +) + second.values.reduce(0, +)
        guard total > 0 else {
            // Lines of at most one character: alike only if they are the same.
            return firstLine.trimmingCharacters(in: .whitespaces) == secondLine.trimmingCharacters(in: .whitespaces) ? 1 : 0
        }
        let common = first.reduce(0) { $0 + min($1.value, second[$1.key] ?? 0) }
        return 2 * Double(common) / Double(total)
    }

    /// The parts of two changed lines that differ, as UTF-16 ranges in each line, for
    /// highlighting within the line. Characters are compared as you see them (an emoji is one).
    /// Very long lines are reported as entirely different.
    public static func changedRanges(left: String, right: String, maximumLength: Int = 2_000) -> (left: [NSRange], right: [NSRange]) {
        let leftCharacters = Array(left), rightCharacters = Array(right)
        guard leftCharacters.count <= maximumLength, rightCharacters.count <= maximumLength else {
            return ([NSRange(location: 0, length: (left as NSString).length)],
                    [NSRange(location: 0, length: (right as NSString).length)])
        }
        // UTF-16 offset of every character, to turn character positions into NSRanges.
        func offsets(_ characters: [Character]) -> [Int] {
            var result: [Int] = [0]
            for character in characters { result.append(result.last! + character.utf16.count) }
            return result
        }
        let leftOffsets = offsets(leftCharacters), rightOffsets = offsets(rightCharacters)
        var leftRanges: [NSRange] = [], rightRanges: [NSRange] = []
        func add(_ index: Int, offsets: [Int], to ranges: inout [NSRange]) {
            let range = NSRange(location: offsets[index], length: offsets[index + 1] - offsets[index])
            if let last = ranges.last, NSMaxRange(last) == range.location {
                ranges[ranges.count - 1].length += range.length   // merge neighbours into one range
            } else {
                ranges.append(range)
            }
        }
        for edit in Diff.edits(from: leftCharacters, to: rightCharacters) {
            switch edit {
            case .same: break
            case .delete(let index): add(index, offsets: leftOffsets, to: &leftRanges)
            case .insert(let index): add(index, offsets: rightOffsets, to: &rightRanges)
            }
        }
        return (leftRanges, rightRanges)
    }
}

/// The two texts prepared for showing side by side: one line per row on both sides, with an
/// empty filler line opposite every added or removed line, so equal lines stay level.
public struct SideBySide: Equatable, Sendable {
    public struct Side: Equatable, Sendable {
        /// The text of each row; "" for a filler row.
        public let lines: [String]
        /// The 1-based line number in the original text for each row; nil for a filler row.
        public let lineNumbers: [Int?]
    }

    public let left: Side
    public let right: Side
    /// The kind of each row (see `TextDiff.Kind`).
    public let kinds: [TextDiff.Kind]
}

extension TextDiff {

    /// `left` and `right` must be the lines this diff was made from.
    public func sideBySide(left: [String], right: [String]) -> SideBySide {
        SideBySide(
            left: SideBySide.Side(lines: rows.map { $0.leftLine.map { left[$0] } ?? "" },
                                  lineNumbers: rows.map { $0.leftLine.map { $0 + 1 } }),
            right: SideBySide.Side(lines: rows.map { $0.rightLine.map { right[$0] } ?? "" },
                                   lineNumbers: rows.map { $0.rightLine.map { $0 + 1 } }),
            kinds: rows.map(\.kind))
    }
}

/// The shortest edit script between two sequences (Myers' O(ND) algorithm, the one `diff` and
/// Git use): which elements stay, which are deleted from the first and inserted from the second.
enum Diff {

    enum Edit: Equatable {
        case same(Int, Int)     // index in old, index in new
        case delete(Int)        // index in old
        case insert(Int)        // index in new
    }

    /// Beyond this many differences, the texts are reported as completely different (the
    /// memory for walking back the path grows with the square of the number of differences).
    static let maximumDifferences = 2_000

    static func edits<Element: Equatable>(from old: [Element], to new: [Element]) -> [Edit] {
        // Equal lines at the start and end are common and cheap: handle them first.
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        var edits = (0..<prefix).map { Edit.same($0, $0) }
        let oldMiddle = Array(old[prefix..<(old.count - suffix)])
        let newMiddle = Array(new[prefix..<(new.count - suffix)])
        edits += middleEdits(oldMiddle, newMiddle).map { edit in
            switch edit {
            case .same(let a, let b): return .same(a + prefix, b + prefix)
            case .delete(let a): return .delete(a + prefix)
            case .insert(let b): return .insert(b + prefix)
            }
        }
        edits += (0..<suffix).map { Edit.same(old.count - suffix + $0, new.count - suffix + $0) }
        return edits
    }

    private static func middleEdits<Element: Equatable>(_ old: [Element], _ new: [Element]) -> [Edit] {
        let n = old.count, m = new.count
        if n == 0 { return (0..<m).map(Edit.insert) }
        if m == 0 { return (0..<n).map(Edit.delete) }

        // `v[k + offset]` is the furthest x reached on diagonal k = x - y; `trace[d]` keeps the
        // part of v for diagonals -d...d before step d, to walk back the path afterwards.
        let maximum = min(n + m, maximumDifferences)
        let offset = maximum + 1
        var v = [Int](repeating: 0, count: 2 * maximum + 3)
        var trace: [[Int]] = []
        var found = false
        search: for d in 0...maximum {
            trace.append(Array(v[(offset - d)...(offset + d)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x = (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset]))
                    ? v[k + 1 + offset]        // down: an insertion
                    : v[k - 1 + offset] + 1    // right: a deletion
                var y = x - k
                while x < n, y < m, old[x] == new[y] { x += 1; y += 1 }   // follow equal elements
                v[k + offset] = x
                if x >= n, y >= m {
                    found = true
                    break search
                }
            }
        }
        guard found else {
            // Too different to align: everything old was removed, everything new added.
            return (0..<n).map(Edit.delete) + (0..<m).map(Edit.insert)
        }

        // Walk back from the end, one difference at a time.
        var edits: [Edit] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let saved = trace[d]   // diagonal k is at index k + d
            func reached(_ k: Int) -> Int { saved[k + d] }
            let k = x - y
            let previousK = (k == -d || (k != d && reached(k - 1) < reached(k + 1))) ? k + 1 : k - 1
            let previousX = d == 0 ? 0 : reached(previousK)
            let previousY = previousX - previousK
            while x > previousX, y > previousY {
                x -= 1; y -= 1
                edits.append(.same(x, y))
            }
            if d > 0 {
                if x == previousX {
                    y -= 1
                    edits.append(.insert(y))
                } else {
                    x -= 1
                    edits.append(.delete(x))
                }
            }
        }
        return edits.reversed()
    }
}
