import Foundation

/// Sorting, reordering, joining, splitting, de-duplicating and trimming lines. Every line keeps
/// its own line break; breaks that are added use the document's style.
public enum LineTools {

    /// Sorts lines the way people expect in their language: "é" next to "e", "a" before "B",
    /// "file2" before "file10". The sort is stable, so equal lines keep their order.
    ///
    /// Locale-aware comparison is slow (microseconds each), so only *distinct* lines are sorted:
    /// lines are grouped by text, the groups are sorted, and each group is written out in its
    /// original order. Files with many repeated lines (formatted JSON, logs) sort much faster.
    static func sort(_ text: String, ascending: Bool, context: TransformContext) -> String {
        let lines = TextLines(text)
        var groups: [String: [Int]] = [:]
        var distinct: [String] = []   // in order of first appearance, which breaks ties
        for (index, line) in lines.lines.enumerated() {
            if groups[line.content] == nil {
                distinct.append(line.content)
            }
            groups[line.content, default: []].append(index)
        }
        // Bridge once: comparing Swift strings with a locale converts them to NSString each time.
        let keys = distinct.map { $0 as NSString }
        let order = keys.indices.sorted { left, right in
            let result = keys[left].compare(keys[right] as String, options: [.caseInsensitive, .numeric],
                                            range: NSRange(location: 0, length: keys[left].length),
                                            locale: context.locale)
            if result == .orderedSame {
                return left < right   // stable: first appearance first
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        let sorted = order.flatMap { groups[distinct[$0], default: []] }.map { lines.lines[$0] }
        return lines.reordered(sorted, lineEnding: context.lineEnding).text
    }

    /// Keeps the first occurrence of each line. Lines are equal when their text is equal,
    /// whatever their line break.
    static func removeDuplicates(_ text: String, context: TransformContext) -> String {
        let lines = TextLines(text)
        var seen = Set<String>()
        let unique = lines.lines.filter { seen.insert($0.content).inserted }
        return lines.reordered(unique, lineEnding: context.lineEnding).text
    }

    /// Removes spaces and tabs (and other horizontal whitespace) at the end of every line.
    /// Line breaks are never touched, so the "\r" of a "\r\n" stays.
    static func trimTrailingWhitespace(_ text: String) -> String {
        var lines = TextLines(text)
        for index in lines.lines.indices {
            let content = lines.lines[index].content
            var end = content.unicodeScalars.endIndex
            while end > content.unicodeScalars.startIndex,
                  CharacterSet.whitespaces.contains(content.unicodeScalars[content.unicodeScalars.index(before: end)]) {
                end = content.unicodeScalars.index(before: end)
            }
            lines.lines[index].content = String(content.unicodeScalars[..<end])
        }
        return lines.text
    }

    /// Reverses the order of the lines.
    static func reverse(_ text: String, context: TransformContext) -> String {
        let lines = TextLines(text)
        return lines.reordered(lines.lines.reversed(), lineEnding: context.lineEnding).text
    }

    /// Puts the lines in random order. Tests pass a seeded generator.
    static func shuffle(_ text: String, context: TransformContext,
                        using generator: inout some RandomNumberGenerator) -> String {
        let lines = TextLines(text)
        return lines.reordered(lines.lines.shuffled(using: &generator), lineEnding: context.lineEnding).text
    }

    /// Removes a line that repeats the line right before it (like the Unix `uniq`), so the same
    /// line further down stays. Lines are equal when their text is equal, whatever their break.
    static func removeConsecutiveDuplicates(_ text: String, context: TransformContext) -> String {
        let lines = TextLines(text)
        var previous: String?
        let kept = lines.lines.filter { line in
            defer { previous = line.content }
            return line.content != previous
        }
        return lines.reordered(kept, lineEnding: context.lineEnding).text
    }

    /// Removes lines that are empty or contain only spaces and tabs.
    static func removeEmptyLines(_ text: String, context: TransformContext) -> String {
        let lines = TextLines(text)
        let kept = lines.lines.filter { !$0.content.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) }
        return lines.reordered(kept, lineEnding: context.lineEnding).text
    }

    /// Joins the lines into one, like "Join Lines" in other editors: the indentation of each
    /// following line is dropped and one space separates the pieces (none if there already is
    /// one, none for empty lines). The last line's break stays, so the text after it stays on
    /// its own line.
    static func join(_ text: String) -> String {
        let lines = TextLines(text)
        guard lines.lines.count > 1 else { return text }
        var result = ""
        for (index, line) in lines.lines.enumerated() {
            var content = Substring(line.content)
            if index > 0 {
                content = content.drop(while: isSpaceOrTab)
                if let last = result.last, !isSpaceOrTab(last), !content.isEmpty {
                    result += " "
                }
            }
            result += content
        }
        return result + (lines.lines.last?.terminator ?? "")
    }

    /// Splits lines longer than `width` characters at spaces and tabs (the space at a split is
    /// removed). A word longer than `width` stays whole; indentation stays on the first piece.
    /// Characters are counted as you see them (an emoji is one); a tab counts as one.
    public static func split(_ text: String, width: Int, context: TransformContext) -> String {
        let lines = TextLines(text)
        var result: [TextLines.Line] = []
        for line in lines.lines {
            let pieces = wrap(line.content, width: width)
            for (index, piece) in pieces.enumerated() {
                let isLast = index == pieces.count - 1
                result.append(.init(content: piece, terminator: isLast ? line.terminator : context.lineEnding.string))
            }
        }
        return TextLines(lines: result).text
    }

    /// One line's content split into pieces of at most `width` characters where possible.
    private static func wrap(_ content: String, width: Int) -> [String] {
        guard width > 0, content.count > width else { return [content] }
        var pieces: [String] = []
        var current = ""
        var currentCount = 0
        var hasWord = false
        var whitespaceBefore: Substring = ""   // the run of spaces before the current word
        var index = content.startIndex
        while index < content.endIndex {
            let isWhitespace = isSpaceOrTab(content[index])
            var end = index
            while end < content.endIndex, isSpaceOrTab(content[end]) == isWhitespace {
                end = content.index(after: end)
            }
            let run = content[index..<end]
            index = end
            if isWhitespace {
                whitespaceBefore = run
                continue
            }
            if !hasWord {
                current = String((pieces.isEmpty ? whitespaceBefore : "") + run)   // indentation only once
                currentCount = current.count
                hasWord = true
            } else if currentCount + whitespaceBefore.count + run.count <= width {
                current += whitespaceBefore + run
                currentCount += whitespaceBefore.count + run.count
            } else {
                pieces.append(current)
                current = String(run)
                currentCount = run.count
            }
            whitespaceBefore = ""
        }
        guard hasWord else { return [content] }   // only spaces and tabs
        pieces.append(current + whitespaceBefore)   // trailing spaces stay where they were
        return pieces
    }

    private static func isSpaceOrTab(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
}
