import Foundation

/// A block that can be folded (collapsed to one line) in the editor.
public struct FoldRegion: Equatable, Sendable {
    /// 0-based line where the block starts; it stays visible when folded and gets the marker.
    public let startLine: Int
    /// 0-based last line of the block.
    public let endLine: Int
    /// The text hidden when folded (UTF-16): between the braces (`{…}`), or from the end of the
    /// first line to the end of the last (`def f():…`).
    public let hiddenRange: NSRange
}

/// How a language's blocks are found.
public enum FoldingStyle: Sendable {
    case none
    /// `{ … }` blocks (and `[ … ]` in JSON) spanning lines; braces in comments and strings don't count.
    case braces
    /// A line followed by more deeply indented lines (Python, YAML …).
    case indentation
    /// A heading up to the next heading of the same or a higher level (Markdown).
    case headings
}

/// Finds the foldable blocks of a document, like the fold markers in Notepad++'s margin.
public enum Folding {

    /// Blocks sorted by start line; at most one per start line (the first that opens there).
    public static func regions(in text: NSString, lineIndex: LineIndex, language: Language) -> [FoldRegion] {
        switch language.foldingStyle {
        case .none: return []
        case .braces: return braceRegions(in: text, lineIndex: lineIndex, grammar: language.grammar,
                                          includesBrackets: language == .json)
        case .indentation: return indentationRegions(in: text, lineIndex: lineIndex)
        case .headings: return headingRegions(in: text, lineIndex: lineIndex)
        }
    }

    // MARK: - Braces

    private static let excludedScopes: Set<SyntaxScope> = [.comment, .string, .stringEscape, .code]

    private static func braceRegions(in text: NSString, lineIndex: LineIndex, grammar: Grammar?,
                                     includesBrackets: Bool) -> [FoldRegion] {
        var open: [(character: unichar, location: Int, line: Int)] = []
        var regions: [Int: FoldRegion] = [:]
        var state = LineState.initial
        for line in 0..<lineIndex.lineCount {
            let content = lineIndex.contentRange(ofLine: line)
            guard content.length > 0 else { continue }
            let lineText = text.substring(with: content) as NSString
            var excluded: [NSRange] = []
            if let grammar {
                let result = grammar.tokenize(line: lineText, startingIn: state)
                state = result.endState
                excluded = result.tokens.filter { excludedScopes.contains($0.scope) }.map(\.range)
            }
            for offset in 0..<lineText.length {
                let character = lineText.character(at: offset)
                let isOpening = character == 0x7B || (includesBrackets && character == 0x5B)    // { [
                let isClosing = character == 0x7D || (includesBrackets && character == 0x5D)    // } ]
                guard isOpening || isClosing,
                      !excluded.contains(where: { NSLocationInRange(offset, $0) }) else { continue }
                if isOpening {
                    open.append((character, content.location + offset, line))
                    continue
                }
                // Close the innermost block of the same kind; an unmatched brace is ignored.
                let matching: unichar = character == 0x7D ? 0x7B : 0x5B
                guard let index = open.lastIndex(where: { $0.character == matching }) else { continue }
                let opening = open[index]
                open.removeSubrange(index...)
                guard line > opening.line, regions[opening.line] == nil || regions[opening.line]!.endLine < line else { continue }
                let start = opening.location + 1
                regions[opening.line] = FoldRegion(startLine: opening.line, endLine: line,
                                                   hiddenRange: NSRange(location: start, length: content.location + offset - start))
            }
        }
        return regions.values.sorted { $0.startLine < $1.startLine }
    }

    // MARK: - Indentation

    private static func indentationRegions(in text: NSString, lineIndex: LineIndex) -> [FoldRegion] {
        // Indentation of each line; nil for blank lines, which belong to whatever surrounds them.
        let indentations: [Int?] = (0..<lineIndex.lineCount).map { indentation(of: lineIndex.contentRange(ofLine: $0), in: text) }
        var regions: [FoldRegion] = []
        for line in 0..<indentations.count {
            guard let indent = indentations[line] else { continue }
            // The block: following lines indented deeper, up to the last non-blank one.
            var last = line
            var next = line + 1
            while next < indentations.count {
                if let nextIndent = indentations[next] {
                    if nextIndent <= indent { break }
                    last = next
                }
                next += 1
            }
            guard last > line else { continue }
            regions.append(region(from: line, to: last, lineIndex: lineIndex))
        }
        return regions
    }

    /// Leading spaces and tabs (a tab counts as 4); nil for a line with nothing else.
    private static func indentation(of content: NSRange, in text: NSString) -> Int? {
        var width = 0
        for index in content.location..<NSMaxRange(content) {
            switch text.character(at: index) {
            case 0x20: width += 1
            case 0x09: width += 4
            default: return width
            }
        }
        return nil
    }

    // MARK: - Headings

    private static func headingRegions(in text: NSString, lineIndex: LineIndex) -> [FoldRegion] {
        // Heading levels by line, from the same patterns as the function list (which skip code blocks).
        let headings = FunctionList.symbols(in: text, lineIndex: lineIndex, language: .markdown)
            .compactMap { symbol -> (line: Int, level: Int)? in
                let content = text.substring(with: lineIndex.contentRange(ofLine: symbol.line))
                let hashes = content.drop(while: { $0 == " " }).prefix(while: { $0 == "#" }).count
                return hashes > 0 ? (symbol.line, hashes) : nil
            }
        var regions: [FoldRegion] = []
        for (index, heading) in headings.enumerated() {
            let nextLine = headings[(index + 1)...].first { $0.level <= heading.level }?.line ?? lineIndex.lineCount
            // Up to the last non-blank line before the next heading.
            var last = nextLine - 1
            while last > heading.line, indentation(of: lineIndex.contentRange(ofLine: last), in: text) == nil {
                last -= 1
            }
            guard last > heading.line else { continue }
            regions.append(region(from: heading.line, to: last, lineIndex: lineIndex))
        }
        return regions
    }

    /// From the end of the first line's text to the end of the last line's text.
    private static func region(from first: Int, to last: Int, lineIndex: LineIndex) -> FoldRegion {
        let start = NSMaxRange(lineIndex.contentRange(ofLine: first))
        let end = NSMaxRange(lineIndex.contentRange(ofLine: last))
        return FoldRegion(startLine: first, endLine: last, hiddenRange: NSRange(location: start, length: end - start))
    }
}

extension Language {

    /// Brace languages fold `{ }`; most others fold by indentation, which fits how code in
    /// them is usually written (Ruby, Lua, Pascal, shell scripts with `if … fi` …).
    /// Plain text doesn't fold.
    public var foldingStyle: FoldingStyle {
        switch self {
        case .plainText, .diff:
            return .none
        case .markdown:
            return .headings
        case .c, .cpp, .csharp, .java, .javaScript, .typeScript, .json, .swift, .go, .rust, .php, .kotlin,
             .scala, .groovy, .dart, .objectiveC, .css, .d, .powerShell, .perl:
            return .braces
        default:
            return .indentation
        }
    }
}
