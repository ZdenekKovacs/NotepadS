import Foundation

/// Re-indents or minifies XML by changing whitespace between tags only, like JSONFormatter:
/// tags, attributes, comments, CDATA and text are copied exactly as written. Badly nested or
/// unfinished XML is reported with its line and column, and nothing changes.
///
/// Not a full XML parser (no DTDs, entities aren't checked): enough for config files, plists,
/// SVG, XAML, Maven and Android files. HTML with unclosed tags (`<br>`) is reported as an error.
enum XMLFormatter {

    /// One element, tag or other piece of the document, as written.
    private enum Node {
        case startTag(name: String, text: String)
        case endTag(name: String, text: String)
        case emptyTag(text: String)                 // <a/>
        case other(text: String)                    // comment, CDATA, <?…?>, <!DOCTYPE …>
        case text(String)
    }

    /// One element per line, children indented by `indent`; an element that contains only text
    /// stays on one line (`<name>Ann</name>`).
    static func format(_ text: String, indent: String, lineEnding: LineEnding) throws -> String {
        let nodes = try parse(text)
        var lines: [String] = []
        var depth = 0
        var index = 0
        func line(_ content: String) {
            lines.append(String(repeating: indent, count: depth) + content)
        }
        while index < nodes.count {
            switch nodes[index] {
            case .startTag(_, let tag):
                // <a>text</a> or <a></a>: keep on one line.
                if index + 2 < nodes.count, case .text(let content) = nodes[index + 1], case .endTag(_, let end) = nodes[index + 2],
                   !content.contains(where: \.isNewline) {
                    line(tag + content + end)
                    index += 3
                    continue
                }
                if index + 1 < nodes.count, case .endTag(_, let end) = nodes[index + 1] {
                    line(tag + end)
                    index += 2
                    continue
                }
                line(tag)
                depth += 1
            case .endTag(_, let tag):
                depth = max(depth - 1, 0)
                line(tag)
            case .emptyTag(let tag), .other(let tag):
                line(tag)
            case .text(let content):
                line(content)
            }
            index += 1
        }
        let endsWithLineBreak = text.utf8.last == 0x0A || text.utf8.last == 0x0D
        return lines.joined(separator: lineEnding.string) + (endsWithLineBreak ? lineEnding.string : "")
    }

    /// Removes whitespace-only text between tags; everything else stays as written.
    static func minify(_ text: String) throws -> String {
        try parse(text).map { node -> String in
            switch node {
            case .startTag(_, let tag), .endTag(_, let tag), .emptyTag(let tag), .other(let tag): return tag
            case .text(let content): return content
            }
        }.joined()
    }

    // MARK: - Reading

    /// The document as nodes. Text nodes are trimmed and whitespace-only ones dropped (that
    /// whitespace is the indentation being replaced). Checks that tags nest correctly.
    private static func parse(_ string: String) throws -> [Node] {
        let text = string as NSString
        var nodes: [Node] = []
        var open: [(name: String, location: Int)] = []
        var position = 0

        func error(_ message: String, at location: Int) -> TransformError {
            let lineIndex = LineIndex(text: text)
            return TransformError(message, line: lineIndex.line(containing: location) + 1,
                                  column: MultiCursor.column(of: location, in: text) + 1)
        }
        /// The location just after `terminator`, searching from `start`; nil if it never comes.
        func end(of terminator: String, from start: Int) -> Int? {
            let found = text.range(of: terminator, options: .literal, range: NSRange(location: start, length: text.length - start))
            return found.location == NSNotFound ? nil : NSMaxRange(found)
        }

        while position < text.length {
            guard text.character(at: position) == 0x3C else {   // "<"
                let next = text.range(of: "<", options: .literal, range: NSRange(location: position, length: text.length - position))
                let stop = next.location == NSNotFound ? text.length : next.location
                let content = text.substring(with: NSRange(location: position, length: stop - position))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    if open.isEmpty {
                        throw error(String(localized: "Text outside the root element.", bundle: .module, comment: "XML error"), at: position)
                    }
                    nodes.append(.text(content))
                }
                position = stop
                continue
            }
            let rest = text.substring(with: NSRange(location: position, length: min(9, text.length - position)))
            let start = position
            if rest.hasPrefix("<!--") {
                guard let stop = end(of: "-->", from: position + 4) else {
                    throw error(String(localized: "The comment is never closed (-->).", bundle: .module, comment: "XML error"), at: start)
                }
                nodes.append(.other(text: text.substring(with: NSRange(location: start, length: stop - start))))
                position = stop
            } else if rest.hasPrefix("<![CDATA[") {
                guard let stop = end(of: "]]>", from: position + 9) else {
                    throw error(String(localized: "The CDATA section is never closed (]]>).", bundle: .module, comment: "XML error"), at: start)
                }
                nodes.append(.other(text: text.substring(with: NSRange(location: start, length: stop - start))))
                position = stop
            } else if rest.hasPrefix("<?") {
                guard let stop = end(of: "?>", from: position + 2) else {
                    throw error(String(localized: "The processing instruction is never closed (?>).", bundle: .module, comment: "XML error"), at: start)
                }
                nodes.append(.other(text: text.substring(with: NSRange(location: start, length: stop - start))))
                position = stop
            } else if rest.hasPrefix("<!") {
                // <!DOCTYPE …>, possibly with an internal subset in [ ].
                guard let stop = tagEnd(in: text, from: position + 2, allowsBrackets: true) else {
                    throw error(String(localized: "The declaration is never closed (>).", bundle: .module, comment: "XML error"), at: start)
                }
                nodes.append(.other(text: text.substring(with: NSRange(location: start, length: stop - start))))
                position = stop
            } else {
                guard let stop = tagEnd(in: text, from: position + 1, allowsBrackets: false) else {
                    throw error(String(localized: "The tag is never closed (>).", bundle: .module, comment: "XML error"), at: start)
                }
                let tag = text.substring(with: NSRange(location: start, length: stop - start))
                let name = tagName(tag)
                guard !name.isEmpty else {
                    throw error(String(localized: "A tag needs a name.", bundle: .module, comment: "XML error"), at: start)
                }
                if tag.hasPrefix("</") {
                    guard let last = open.last else {
                        throw error(String(localized: "“</\(name)>” has no opening tag.", bundle: .module, comment: "XML error"), at: start)
                    }
                    guard last.name == name else {
                        throw error(String(localized: "Expected “</\(last.name)>”, found “</\(name)>”.", bundle: .module, comment: "XML error"), at: start)
                    }
                    open.removeLast()
                    nodes.append(.endTag(name: name, text: tag))
                } else if tag.hasSuffix("/>") {
                    nodes.append(.emptyTag(text: tag))
                } else {
                    open.append((name, start))
                    nodes.append(.startTag(name: name, text: tag))
                }
                position = stop
            }
        }
        if let unclosed = open.last {
            throw error(String(localized: "“<\(unclosed.name)>” is never closed.", bundle: .module, comment: "XML error"), at: unclosed.location)
        }
        return nodes
    }

    /// The location after the `>` that ends a tag starting before `start`. A `>` inside a quoted
    /// attribute value doesn't end it; with `allowsBrackets`, neither does one inside `[ ]`.
    private static func tagEnd(in text: NSString, from start: Int, allowsBrackets: Bool) -> Int? {
        var quote: unichar?
        var bracketDepth = 0
        var index = start
        while index < text.length {
            let unit = text.character(at: index)
            if let open = quote {
                if unit == open { quote = nil }
            } else if unit == 0x22 || unit == 0x27 {          // " '
                quote = unit
            } else if allowsBrackets && unit == 0x5B {        // [
                bracketDepth += 1
            } else if allowsBrackets && unit == 0x5D {        // ]
                bracketDepth -= 1
            } else if unit == 0x3E && bracketDepth <= 0 {     // >
                return index + 1
            } else if unit == 0x3C && !allowsBrackets {       // < inside a tag: it was never closed
                return nil
            }
            index += 1
        }
        return nil
    }

    /// "a:b" from "<a:b x='1'>", "</a:b>" or "<a:b/>".
    private static func tagName(_ tag: String) -> String {
        let body = tag.drop(while: { $0 == "<" || $0 == "/" })
        return String(body.prefix(while: { !$0.isWhitespace && $0 != ">" && $0 != "/" }))
    }
}
