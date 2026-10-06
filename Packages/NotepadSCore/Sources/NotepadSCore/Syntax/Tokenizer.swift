import Foundation

/// The tokenizer's state between lines: which spans (block comment, multi-line string, …) are
/// still open at the start of a line. The highlighter stores one per line.
public struct LineState: Hashable, Sendable {
    /// Open spans, innermost last.
    var openSpans: [SpanID] = []

    /// The state at the start of a document: nothing open.
    public static let initial = LineState()

    /// True while a span such as a block comment continues past the line.
    public var isInsideSpan: Bool { !openSpans.isEmpty }
}

/// A colored piece of a line.
public struct SyntaxToken: Equatable, Sendable {
    /// UTF-16 range relative to the start of the line (the unit of `NSRange`).
    public let range: NSRange
    public let scope: SyntaxScope

    public init(range: NSRange, scope: SyntaxScope) {
        self.range = range
        self.scope = scope
    }
}

extension Grammar {

    /// Splits one line into colored tokens.
    ///
    /// - Parameters:
    ///   - line: the line's text **without** its line break.
    ///   - state: the state at the start of the line (`.initial` for the first line, otherwise
    ///     the `endState` of the previous line).
    /// - Returns: non-overlapping tokens in order (uncolored text has no token), and the state at
    ///   the end of the line.
    public func tokenize(line: NSString, startingIn state: LineState) -> (tokens: [SyntaxToken], endState: LineState) {
        var tokens: [SyntaxToken] = []
        var openSpans = state.openSpans
        var position = 0
        // Where the innermost open span's own coloring resumes (after its last inner token).
        var spanTextStart = 0
        var search = MatchSearch(line: line)

        func colorSpanText(upTo end: Int) {
            guard let span = openSpans.last, end > spanTextStart else { return }
            tokens.append(SyntaxToken(range: NSRange(location: spanTextStart, length: end - spanTextStart),
                                      scope: spans[span].scope))
        }

        while position <= line.length {
            let rules = openSpans.last.map { spans[$0].rules } ?? rootRules
            guard let next = earliestMatch(from: position, openSpan: openSpans.last, rules: rules, search: &search) else {
                break
            }
            let matchEnd = NSMaxRange(next.range)
            switch next.kind {
            case .spanEnd:
                // The span's color covers its end delimiter too.
                colorSpanText(upTo: matchEnd)
                openSpans.removeLast()
            case .match(let scope):
                colorSpanText(upTo: next.range.location)
                tokens.append(SyntaxToken(range: next.range, scope: scope))
            case .spanBegin(let span):
                colorSpanText(upTo: next.range.location)
                openSpans.append(span)
            }
            // The begin delimiter belongs to the new span; after an end or a match, coloring
            // of the enclosing span resumes here.
            spanTextStart = next.kind.isSpanBegin ? next.range.location : matchEnd
            position = matchEnd
        }
        colorSpanText(upTo: line.length)
        return (tokens, LineState(openSpans: openSpans))
    }

    // MARK: - Finding the next match

    private enum MatchKind {
        case spanEnd
        case match(SyntaxScope)
        case spanBegin(SpanID)

        var isSpanBegin: Bool {
            if case .spanBegin = self { return true }
            return false
        }
    }

    private struct FoundMatch {
        let range: NSRange
        let kind: MatchKind
    }

    /// The earliest match at or after `position`. The open span's end pattern wins ties, then
    /// rules in the order they are listed.
    private func earliestMatch(from position: Int, openSpan: SpanID?, rules: [CompiledRule],
                               search: inout MatchSearch) -> FoundMatch? {
        var best: FoundMatch?
        let ruleList = openSpan ?? -1

        func consider(_ range: NSRange?, _ kind: MatchKind) {
            guard let range else { return }
            if let current = best, current.range.location <= range.location { return }
            best = FoundMatch(range: range, kind: kind)
        }

        if let openSpan {
            // An end pattern may match empty text (e.g. `$`): closing a span is always progress.
            consider(search.firstMatch(of: spans[openSpan].end, key: .end(openSpan), from: position, allowEmpty: true),
                     .spanEnd)
        }
        for (index, rule) in rules.enumerated() {
            switch rule {
            case .match(let regex, let scope):
                consider(search.firstMatch(of: regex, key: .rule(list: ruleList, index: index), from: position,
                                           allowEmpty: false), .match(scope))
            case .span(let span):
                consider(search.firstMatch(of: spans[span].begin, key: .rule(list: ruleList, index: index), from: position,
                                           allowEmpty: false),
                         .spanBegin(span))
            }
        }
        return best
    }
}

/// Runs regex searches on one line and remembers results, so each rule's regex runs about once
/// per line instead of once per token.
private struct MatchSearch {
    /// Results are kept per regex, across spans opening and closing: after a string closes,
    /// the line's other rules don't need to be searched again (a line with thousands of short
    /// strings would otherwise take seconds).
    enum Key: Hashable {
        /// The end pattern of a span.
        case end(SpanID)
        /// Rule `index` of a rule list: the top level (`list` -1) or a span's own rules.
        case rule(list: Int, index: Int)
    }

    let line: NSString
    /// The first match found for a key, or nil if there is none until the end of the line.
    private var cache: [Key: NSRange?] = [:]

    init(line: NSString) {
        self.line = line
    }

    mutating func firstMatch(of regex: NSRegularExpression, key: Key, from position: Int, allowEmpty: Bool) -> NSRange? {
        if let cached = cache[key] {
            // A match found from an earlier position that starts at or after `position` is also
            // the first match from `position`. No match from earlier means none from later.
            guard let range = cached else { return nil }
            if range.location >= position { return range }
        }
        let range = search(regex, from: position, allowEmpty: allowEmpty)
        cache[key] = .some(range)
        return range
    }

    /// `withoutAnchoringBounds` keeps `^` and `$` meaning start and end of the line even when the
    /// search starts mid-line; `withTransparentBounds` lets `\b` and lookbehind see the text
    /// before the search position.
    private func search(_ regex: NSRegularExpression, from position: Int, allowEmpty: Bool) -> NSRange? {
        var start = position
        while start <= line.length {
            let range = NSRange(location: start, length: line.length - start)
            guard let match = regex.firstMatch(in: line as String, options: [.withTransparentBounds, .withoutAnchoringBounds],
                                               range: range) else { return nil }
            if match.range.length > 0 || allowEmpty {
                return match.range
            }
            // Empty matches of match/begin rules would never advance; look further along.
            start = match.range.location + 1
        }
        return nil
    }
}
