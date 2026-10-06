import Foundation

/// A text split into lines, each keeping its own line break, for line-based transformations.
///
/// Understands `\n`, `\r\n` and `\r`, also mixed. Joining the lines again gives back the text
/// byte for byte, so a transformation that changes nothing changes nothing.
public struct TextLines: Equatable, Sendable {

    public struct Line: Equatable, Sendable {
        /// The line without its break.
        public var content: String
        /// The break that ends the line: "\n", "\r\n", "\r", or "" for a last line without one.
        public var terminator: String

        public init(content: String, terminator: String) {
            self.content = content
            self.terminator = terminator
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    /// Splits `text` into lines. A text ending with a break has no empty line after it here
    /// (unlike the editor's line numbers), so "a\nb\n" is two lines.
    public init(_ text: String) {
        // Scan UTF-8 bytes: "\r" and "\n" are single bytes that never occur inside a multi-byte
        // character, and in Swift "\r\n" is one Character, so a Character scan would miss them.
        let bytes = text.utf8
        var lines: [Line] = []
        var lineStart = bytes.startIndex
        var index = bytes.startIndex
        while index != bytes.endIndex {
            let byte = bytes[index]
            guard byte == Byte.lineFeed || byte == Byte.carriageReturn else {
                index = bytes.index(after: index)
                continue
            }
            let content = String(decoding: bytes[lineStart..<index], as: UTF8.self)
            var next = bytes.index(after: index)
            var terminator = byte == Byte.lineFeed ? "\n" : "\r"
            if byte == Byte.carriageReturn, next != bytes.endIndex, bytes[next] == Byte.lineFeed {
                next = bytes.index(after: next)
                terminator = "\r\n"
            }
            lines.append(Line(content: content, terminator: terminator))
            lineStart = next
            index = next
        }
        if lineStart != bytes.endIndex {
            lines.append(Line(content: String(decoding: bytes[lineStart...], as: UTF8.self), terminator: ""))
        }
        self.lines = lines
    }

    /// The text again: every line's content followed by its own break.
    public var text: String {
        lines.map { $0.content + $0.terminator }.joined()
    }

    /// Replaces the lines with `newOrder` (lines of this text, reordered or filtered), fixing the
    /// breaks that moved: a line that ends up last keeps the original text's final break (or
    /// none), and a line without a break that ends up in the middle gets `lineEnding`. Every
    /// other line keeps its own break, so the file's line-break styles stay as they were.
    public func reordered(_ newOrder: [Line], lineEnding: LineEnding) -> TextLines {
        let endsWithBreak = !(lines.last?.terminator.isEmpty ?? true)
        var result = newOrder
        for index in result.indices {
            let isLast = index == result.count - 1
            if isLast && !endsWithBreak {
                result[index].terminator = ""
            } else if result[index].terminator.isEmpty {
                result[index].terminator = lineEnding.string
            }
        }
        return TextLines(lines: result)
    }
}
