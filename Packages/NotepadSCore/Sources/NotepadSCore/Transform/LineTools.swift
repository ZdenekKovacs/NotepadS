import Foundation

/// Sorting, de-duplicating and trimming lines. Every line keeps its own line break.
enum LineTools {

    /// Sorts lines the way people expect in their language: "é" next to "e", "a" before "B",
    /// "file2" before "file10". The sort is stable, so equal lines keep their order.
    static func sort(_ text: String, ascending: Bool, context: TransformContext) -> String {
        let lines = TextLines(text)
        let sorted = lines.lines.enumerated().sorted { left, right in
            let order = left.element.content.compare(right.element.content,
                                                     options: [.caseInsensitive, .numeric],
                                                     range: nil, locale: context.locale)
            if order == .orderedSame {
                return left.offset < right.offset   // stable
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.map(\.element)
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
