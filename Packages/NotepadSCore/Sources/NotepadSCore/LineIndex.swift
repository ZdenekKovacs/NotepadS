import Foundation

/// Where each line starts, and the style of each line break, for a text stored in an
/// `NSString` (the storage behind `NSTextStorage`).
///
/// - A line break is `\r\n`, `\r` or `\n`. A `\r\n` pair is always one break.
/// - Positions are UTF-16 offsets, like `NSRange`.
/// - Line numbers here are 0-based; the UI adds 1.
/// - A text always has at least one line. A text ending with a break has an empty last line.
///
/// `applyEdit` updates the index after an edit by rescanning only the lines around it, so
/// typing stays fast in large files. The per-style counts (and therefore "dominant style" and
/// "mixed") are kept up to date without rescanning the whole text.
public struct LineIndex: Equatable, Sendable {

    /// `lineStarts[i]` is the offset where line `i` starts. Always starts with 0.
    public private(set) var lineStarts: [Int] = [0]
    /// `breakStyles[i]` is the break that ends line `i`. The last line has no break, so
    /// there is one entry less than in `lineStarts`.
    public private(set) var breakStyles: [LineEnding] = []
    /// Number of breaks of each style.
    public private(set) var counts = LineEndingCounts()
    /// Length of the indexed text in UTF-16 units.
    public private(set) var textLength = 0

    public init() {}

    public init(text: NSString) {
        rebuild(from: text)
    }

    public var lineCount: Int { lineStarts.count }

    public func lineStart(of line: Int) -> Int {
        lineStarts[line]
    }

    /// The range of `line` without its line break.
    public func contentRange(ofLine line: Int) -> NSRange {
        let start = lineStarts[line]
        let end = line + 1 < lineStarts.count
            ? lineStarts[line + 1] - breakStyles[line].utf16Length
            : textLength
        return NSRange(location: start, length: end - start)
    }

    /// The range of `line` including its line break.
    public func fullRange(ofLine line: Int) -> NSRange {
        let start = lineStarts[line]
        let end = line + 1 < lineStarts.count ? lineStarts[line + 1] : textLength
        return NSRange(location: start, length: end - start)
    }

    /// The line containing `offset`. An offset inside or right before a line break belongs to
    /// the line the break ends; `textLength` belongs to the last line.
    public func line(containing offset: Int) -> Int {
        // Binary search for the last line start <= offset.
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// 1-based column of `offset`, counted in user-perceived characters (a tab, an emoji and
    /// "ř" are one column each). Lines longer than `longLineThreshold` count UTF-16 units
    /// instead, so the status bar stays instant.
    public func column(of offset: Int, in text: NSString, longLineThreshold: Int = 10_000) -> Int {
        let line = line(containing: offset)
        let content = contentRange(ofLine: line)
        // Inside a "\r\n" pair (not a real caret position) counts as the end of the content.
        let end = min(offset, NSMaxRange(content))
        let length = end - content.location
        guard length > 0 else { return 1 }
        guard content.length <= longLineThreshold else { return length + 1 }
        return text.substring(with: NSRange(location: content.location, length: length)).count + 1
    }

    // MARK: - Building and updating

    /// Indexes the whole text.
    public mutating func rebuild(from text: NSString) {
        lineStarts = [0]
        breakStyles = []
        counts = LineEndingCounts()
        textLength = text.length
        LineBreakScanner.scan(text, from: 0) { _, end, style in
            lineStarts.append(end)
            breakStyles.append(style)
            counts.add(style)
            return false
        }
    }

    /// Updates the index after an edit of the text.
    ///
    /// Takes the values `NSTextStorage` reports after an edit:
    /// - Parameters:
    ///   - editedRange: the range of the new characters, in the new text.
    ///   - changeInLength: new length minus old length.
    ///   - text: the text after the edit.
    public mutating func applyEdit(editedRange: NSRange, changeInLength: Int, in text: NSString) {
        let newEditStart = editedRange.location
        let newEditEnd = NSMaxRange(editedRange)

        // Start rescanning at the start of the line containing the edit. If the previous line
        // ends with a lone "\r", start one line earlier: the edit may begin with "\n" and join
        // that "\r" into a "\r\n" break.
        var firstLine = line(containing: newEditStart)
        if firstLine > 0, breakStyles[firstLine - 1] == .cr {
            firstLine -= 1
        }
        let rescanStart = lineStarts[firstLine]

        // Rescan until a break that lies completely after the edit and ends where an old line
        // started (shifted by the change in length). From there on, the old index is still
        // right. The break must start at or after the edit's end, so the scanner has already
        // seen any "\r" from the edit that could join with it.
        var newStarts: [Int] = []
        var newStyles: [LineEnding] = []
        var resumeLine: Int?   // old line whose start matched; old entries from it on are kept
        LineBreakScanner.scan(text, from: rescanStart) { start, end, style in
            newStarts.append(end)
            newStyles.append(style)
            // A break made only of unchanged characters also ended a line in the old text,
            // so the lookup succeeds whenever this first guard passes.
            guard start >= newEditEnd,
                  let oldLine = oldLineIndex(ofStart: end - changeInLength, after: firstLine) else { return false }
            resumeLine = oldLine
            return true
        }

        // Replace old lines firstLine+1 ... resumeLine (or to the end) with the rescanned ones.
        let replaceEnd = resumeLine.map { $0 + 1 } ?? lineStarts.count
        for style in breakStyles[firstLine..<(replaceEnd - 1)] {
            counts.add(style, count: -1)
        }
        for style in newStyles {
            counts.add(style)
        }
        breakStyles.replaceSubrange(firstLine..<(replaceEnd - 1), with: newStyles)
        lineStarts.replaceSubrange((firstLine + 1)..<replaceEnd, with: newStarts)
        if changeInLength != 0 {
            for index in (firstLine + 1 + newStarts.count)..<lineStarts.count {
                lineStarts[index] += changeInLength
            }
        }
        textLength = text.length
    }

    /// Index of the old line that starts at `offset`, searching lines after `line`.
    private func oldLineIndex(ofStart offset: Int, after line: Int) -> Int? {
        var low = line + 1
        var high = lineStarts.count - 1
        while low <= high {
            let middle = (low + high) / 2
            if lineStarts[middle] == offset {
                return middle
            } else if lineStarts[middle] < offset {
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return nil
    }
}

/// Finds line breaks in an `NSString`, reading it in chunks of UTF-16 units.
///
/// Reading chunks with `getCharacters(_:range:)` is much faster than calling
/// `character(at:)` per unit. `\r` and `\n` are never part of a surrogate pair, so a
/// UTF-16 scan is exact.
enum LineBreakScanner {
    private static let chunkSize = 16 * 1024

    /// Calls `body(start, end, style)` for each break at or after `startOffset`; `end` is the
    /// offset after the break (where the next line starts). Stops when `body` returns true.
    static func scan(_ text: NSString, from startOffset: Int,
                     _ body: (_ start: Int, _ end: Int, _ style: LineEnding) -> Bool) {
        let length = text.length
        var buffer = [unichar](repeating: 0, count: chunkSize)
        var chunkStart = startOffset
        var pendingCR: Int?   // offset of a "\r" whose next unit hasn't been read yet

        while chunkStart < length {
            let chunkLength = min(chunkSize, length - chunkStart)
            buffer.withUnsafeMutableBufferPointer { pointer in
                // The buffer has chunkSize elements, so the base address is never nil.
                text.getCharacters(pointer.baseAddress!, range: NSRange(location: chunkStart, length: chunkLength))
            }
            for index in 0..<chunkLength {
                let unit = buffer[index]
                let offset = chunkStart + index
                if let crOffset = pendingCR {
                    pendingCR = nil
                    if unit == UTF16Unit.lineFeed {
                        if body(crOffset, offset + 1, .crlf) { return }
                        continue
                    }
                    if body(crOffset, crOffset + 1, .cr) { return }
                }
                if unit == UTF16Unit.carriageReturn {
                    pendingCR = offset
                } else if unit == UTF16Unit.lineFeed {
                    if body(offset, offset + 1, .lf) { return }
                }
            }
            chunkStart += chunkLength
        }
        if let crOffset = pendingCR {
            _ = body(crOffset, crOffset + 1, .cr)
        }
    }
}
