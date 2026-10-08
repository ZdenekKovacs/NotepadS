import Foundation

/// Text › Whitespace: trimming, tabs ↔ spaces, line breaks → spaces. Works line by line; line
/// breaks are never touched, except by `lineBreaksToSpaces`.
enum WhitespaceTools {

    /// Removes spaces and tabs (and other horizontal whitespace) at the start of every line.
    static func trimLeading(_ text: String) -> String {
        var lines = TextLines(text)
        for index in lines.lines.indices {
            let scalars = lines.lines[index].content.unicodeScalars
            let start = scalars.firstIndex { !CharacterSet.whitespaces.contains($0) } ?? scalars.endIndex
            lines.lines[index].content = String(scalars[start...])
        }
        return lines.text
    }

    /// Replaces every tab with spaces up to the next tab stop, so the text looks the same.
    /// Columns count characters as you see them (an emoji is one).
    static func tabsToSpaces(_ text: String, tabWidth: Int) -> String {
        let tabWidth = max(tabWidth, 1)
        var lines = TextLines(text)
        for index in lines.lines.indices where lines.lines[index].content.contains("\t") {
            var result = ""
            var column = 0
            for character in lines.lines[index].content {
                if character == "\t" {
                    let spaces = tabWidth - column % tabWidth
                    result += String(repeating: " ", count: spaces)
                    column += spaces
                } else {
                    result.append(character)
                    column += 1
                }
            }
            lines.lines[index].content = result
        }
        return lines.text
    }

    /// Rewrites each line's indentation (its leading spaces and tabs) as tabs, plus spaces for
    /// the rest of a tab stop. The indentation keeps its width; spaces after the first other
    /// character stay.
    static func leadingSpacesToTabs(_ text: String, tabWidth: Int) -> String {
        let tabWidth = max(tabWidth, 1)
        var lines = TextLines(text)
        for index in lines.lines.indices {
            let content = lines.lines[index].content
            let indentationEnd = content.firstIndex { $0 != " " && $0 != "\t" } ?? content.endIndex
            var width = 0
            for character in content[..<indentationEnd] {
                width = character == "\t" ? (width / tabWidth + 1) * tabWidth : width + 1
            }
            let indentation = String(repeating: "\t", count: width / tabWidth) + String(repeating: " ", count: width % tabWidth)
            lines.lines[index].content = indentation + content[indentationEnd...]
        }
        return lines.text
    }

    /// Replaces each line break with one space, joining the lines literally (unlike Join Lines,
    /// nothing is trimmed). The last line's break stays.
    static func lineBreaksToSpaces(_ text: String) -> String {
        let lines = TextLines(text)
        var result = ""
        for (index, line) in lines.lines.enumerated() {
            let isLast = index == lines.lines.count - 1
            result += line.content + (isLast ? line.terminator : " ")
        }
        return result
    }
}
