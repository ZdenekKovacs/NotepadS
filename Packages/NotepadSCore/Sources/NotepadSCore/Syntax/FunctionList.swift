import Foundation

/// A function, type, heading … found in a document, for the Function List.
public struct CodeSymbol: Equatable, Sendable {
    public enum Kind: Sendable {
        /// Functions, methods, procedures, subroutines.
        case function
        /// Classes, structs, interfaces, modules, namespaces.
        case type
        /// Markdown and LaTeX headings.
        case heading
        /// INI/TOML sections, Make targets, labels, CSS selectors, YAML keys …
        case section
    }

    public let name: String
    public let kind: Kind
    /// 0-based line number.
    public let line: Int
    /// Where the name is in the text (UTF-16 offsets), for jumping to it.
    public let range: NSRange
    /// Nesting for display: 0 for the outermost symbols. From the indentation (methods indented
    /// inside a class come out one deeper) or, for headings, from the heading level.
    public let depth: Int
}

/// Finds the functions, types and headings of a document with per-language patterns
/// (`Language.symbolRules`), like Notepad++'s Function List.
///
/// Patterns look at one line at a time, so this is a good guess, not a parser: a definition
/// split over several lines is found only if its name is on the line the pattern expects.
/// Matches inside comments and strings are skipped (the grammar's tokens tell where those are).
public enum FunctionList {

    /// Scopes in which a match isn't a definition.
    private static let excludedScopes: Set<SyntaxScope> = [.comment, .string, .stringEscape, .code]

    public static func symbols(in text: NSString, lineIndex: LineIndex, language: Language) -> [CodeSymbol] {
        let rules = language.symbolRules
        guard !rules.isEmpty else { return [] }
        let grammar = language.grammar
        var state = LineState.initial
        var found: [(name: String, kind: CodeSymbol.Kind, line: Int, range: NSRange, indentation: Int)] = []

        for line in 0..<lineIndex.lineCount {
            let content = lineIndex.contentRange(ofLine: line)
            let lineText = text.substring(with: content) as NSString
            // Tokenize every line, also those without a match: a comment or string may span lines.
            let tokens: [SyntaxToken]
            if let grammar {
                let result = grammar.tokenize(line: lineText, startingIn: state)
                tokens = result.tokens
                state = result.endState
            } else {
                tokens = []
            }
            guard lineText.length > 0 else { continue }
            for rule in rules {
                guard let match = rule.regex.firstMatch(in: lineText as String, range: NSRange(location: 0, length: lineText.length)),
                      let nameRange = rule.nameRange(in: match), nameRange.location != NSNotFound else { continue }
                let isExcluded = tokens.contains { token in
                    excludedScopes.contains(token.scope) && NSLocationInRange(nameRange.location, token.range)
                }
                if isExcluded { break }   // this line's definition is commented out or quoted
                let name = lineText.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { break }
                let indentation = rule.headingLevel(in: match, text: lineText) ?? indentationWidth(of: lineText)
                found.append((name, rule.kind, line,
                              NSRange(location: content.location + nameRange.location, length: nameRange.length),
                              indentation))
                break   // one symbol per line, from the first rule that matches
            }
        }

        // Depth: the rank of each indentation among those used, so 0, 4 and 8 spaces (or
        // heading levels 1, 2, 3) become depths 0, 1, 2, and a file indented with 2 spaces
        // nests the same way.
        let levels = Array(Set(found.map(\.indentation))).sorted()
        let depthOfIndentation = Dictionary(uniqueKeysWithValues: levels.enumerated().map { ($1, $0) })
        return found.map {
            CodeSymbol(name: $0.name, kind: $0.kind, line: $0.line, range: $0.range,
                       depth: depthOfIndentation[$0.indentation] ?? 0)
        }
    }

    /// Leading spaces and tabs in columns; a tab counts as 4.
    private static func indentationWidth(of line: NSString) -> Int {
        var width = 0
        for index in 0..<line.length {
            switch line.character(at: index) {
            case 0x20: width += 1
            case 0x09: width += 4
            default: return width
            }
        }
        return width
    }
}

/// One pattern that recognizes a definition: the named group `name` is the symbol's name, an
/// optional group `level` (e.g. Markdown's `#` signs) sets a heading's level.
struct SymbolRule: Sendable {
    let regex: NSRegularExpression
    let kind: CodeSymbol.Kind

    init(_ pattern: String, _ kind: CodeSymbol.Kind, ignoringCase: Bool = false) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: ignoringCase ? [.caseInsensitive] : [])
        } catch {
            // Patterns are fixed data written by us and covered by tests.
            preconditionFailure("Invalid symbol pattern \(pattern): \(error)")
        }
        self.kind = kind
    }

    func nameRange(in match: NSTextCheckingResult) -> NSRange? {
        let range = match.range(withName: "name")
        return range.location == NSNotFound ? nil : range
    }

    /// For headings: the length of the `level` group ("##" → 2), or the index of a LaTeX
    /// sectioning command; nil when the pattern has no level.
    func headingLevel(in match: NSTextCheckingResult, text: NSString) -> Int? {
        guard regex.pattern.contains("(?<level>") else { return nil }
        let range = match.range(withName: "level")
        guard range.location != NSNotFound else { return nil }
        let level = text.substring(with: range)
        if let index = ["part", "chapter", "section", "subsection", "subsubsection", "paragraph"].firstIndex(of: level) {
            return index
        }
        return range.length
    }
}
