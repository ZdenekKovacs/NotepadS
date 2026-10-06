import Foundation

/// Sorting, de-duplicating and trimming lines. Every line keeps its own line break.
enum LineTools {

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
}
