import Foundation

/// Bookmarked lines (Edit › Bookmarks), like Notepad++'s bookmarks: marked in the gutter,
/// visited with Next/Previous, copied or removed together. Kept by line number; edits move
/// them with their lines.
public struct Bookmarks: Equatable, Sendable {

    /// 0-based line numbers.
    public private(set) var lines: Set<Int> = []

    public init(lines: Set<Int> = []) {
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }

    public mutating func toggle(_ line: Int) {
        if lines.contains(line) {
            lines.remove(line)
        } else {
            lines.insert(line)
        }
    }

    public mutating func removeAll() {
        lines = []
    }

    /// The next bookmark after `line`, wrapping around to the first.
    public func next(after line: Int) -> Int? {
        lines.filter { $0 > line }.min() ?? lines.min()
    }

    /// The previous bookmark before `line`, wrapping around to the last.
    public func previous(before line: Int) -> Int? {
        lines.filter { $0 < line }.max() ?? lines.max()
    }

    /// Moves bookmarks after an edit (from `LineIndex.applyEditReportingLines`): lines after the
    /// edited ones shift by the number of lines added or removed; a bookmark on a line that was
    /// removed goes to the edit's first line; lines beyond `lineCount` are dropped.
    public mutating func apply(_ change: LineChange, lineCount: Int) {
        guard !lines.isEmpty else { return }
        lines = Set(lines.compactMap { line -> Int? in
            let moved: Int
            if line <= change.firstLine {
                moved = line
            } else if line > change.oldLastLine {
                moved = line + change.lineCountDelta
            } else {
                // Inside the edit: stays if its line still exists there, else joins the first line.
                moved = min(line, change.newLastLine)
            }
            return moved < lineCount ? moved : nil
        })
    }
}
