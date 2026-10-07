import Foundation

/// What a piece of text is, for coloring. Themes map each scope to a color.
public enum SyntaxScope: String, CaseIterable, Hashable, Sendable {
    case comment
    case string
    /// An escape sequence inside a string, such as `\n` or `\"`.
    case stringEscape
    case number
    case keyword
    /// Built-in constants: `true`, `false`, `null`, `None`.
    case constant
    /// Object keys (JSON), attribute names.
    case property
    /// Variables such as `$HOME` in shell scripts.
    case variable
    /// Function and command names.
    case function
    case `operator`
    case heading
    case emphasis
    case strong
    /// Inline code and code blocks in Markdown.
    case code
    case link
    /// Added lines in a diff.
    case inserted
    /// Removed lines in a diff.
    case deleted
}

/// A language's highlighting rules, written as data.
///
/// Two kinds of rules (see `Rule`):
/// - **match** rules color one regex match inside a line (a keyword, a number, a `//` comment);
/// - **span** rules start at one regex and run until another, possibly over many lines
///   (a `/* … */` comment, a Python `"""` string, a Markdown code fence). Spans can contain
///   their own rules, e.g. escapes inside a string.
///
/// Rules are tried at each position in order; the earliest match wins, ties go to the rule
/// listed first. Patterns are matched against one line at a time, without its line break,
/// so `^` and `$` mean start and end of the line.
public struct Grammar: Sendable {
    /// Shown in the status bar, e.g. "JSON".
    public let name: String
    /// Rules at the top level (outside any span).
    let rootRules: [CompiledRule]
    /// Every span of the grammar, indexed by `SpanID`.
    let spans: [CompiledSpan]

    public init(name: String, rules: [Rule]) {
        var spans: [CompiledSpan] = []
        self.name = name
        self.rootRules = Grammar.compile(rules, into: &spans)
        self.spans = spans
    }

    /// Compiles rules depth-first; each span gets the next free ID.
    private static func compile(_ rules: [Rule], into spans: inout [CompiledSpan]) -> [CompiledRule] {
        rules.map { rule in
            switch rule.kind {
            case .match(let pattern, let scope):
                return .match(Grammar.regex(pattern), scope)
            case .span(let begin, let end, let scope, let innerRules):
                let id = spans.count
                // Reserve the slot first so nested spans get later IDs.
                spans.append(CompiledSpan(begin: Grammar.regex(begin), end: Grammar.regex(end), scope: scope, rules: []))
                let inner = compile(innerRules, into: &spans)
                spans[id].rules = inner
                return .span(id)
            }
        }
    }

    /// Patterns are fixed data written by us and covered by tests; an invalid one is a
    /// programming error, so stop immediately with the pattern in the message.
    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            preconditionFailure("Invalid grammar pattern \(pattern): \(error)")
        }
    }
}

/// One highlighting rule. Build rules with the static functions.
public struct Rule: Sendable {
    enum Kind: Sendable {
        case match(pattern: String, scope: SyntaxScope)
        case span(begin: String, end: String, scope: SyntaxScope, rules: [Rule])
    }

    let kind: Kind

    /// Colors each match of `pattern` within a line. Empty matches are ignored.
    public static func match(_ pattern: String, _ scope: SyntaxScope) -> Rule {
        Rule(kind: .match(pattern: pattern, scope: scope))
    }

    /// Colors whole words from a list, e.g. keywords.
    public static func words(_ words: [String], _ scope: SyntaxScope) -> Rule {
        let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return match("\\b(?:\(alternatives))\\b", scope)
    }

    /// Colors whole words from a list in any letter case, for languages such as Pascal, Ada,
    /// Fortran, COBOL or Visual Basic, where `BEGIN`, `Begin` and `begin` are the same word.
    /// Longer words are tried first. With `hyphenated` (COBOL), a hyphen is part of a word:
    /// "end-if" is one word, and "end" doesn't match inside it.
    public static func wordsIgnoringCase(_ words: [String], _ scope: SyntaxScope, hyphenated: Bool = false) -> Rule {
        let alternatives = words.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return hyphenated
            ? match("(?i)(?<![\\w-])(?:\(alternatives))(?![\\w-])", scope)
            : match("(?i)\\b(?:\(alternatives))\\b", scope)
    }

    /// Colors everything from a match of `begin` through the next match of `end`, across lines.
    /// `rules` apply inside the span (they win over the span's own scope).
    public static func span(_ begin: String, _ end: String, _ scope: SyntaxScope, rules: [Rule] = []) -> Rule {
        Rule(kind: .span(begin: begin, end: end, scope: scope, rules: rules))
    }
}

typealias SpanID = Int

enum CompiledRule: @unchecked Sendable {   // NSRegularExpression is immutable and thread-safe
    case match(NSRegularExpression, SyntaxScope)
    case span(SpanID)
}

struct CompiledSpan: @unchecked Sendable {
    let begin: NSRegularExpression
    let end: NSRegularExpression
    let scope: SyntaxScope
    var rules: [CompiledRule]
}
