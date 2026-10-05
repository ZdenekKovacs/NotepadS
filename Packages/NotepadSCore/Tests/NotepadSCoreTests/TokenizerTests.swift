import XCTest
@testable import NotepadSCore

final class TokenizerTests: XCTestCase {

    /// A small C-like language that exercises every kind of rule.
    private let grammar = Grammar(name: "Test", rules: [
        .match("//.*$", .comment),
        .span("/\\*", "\\*/", .comment),
        .span("\"\"\"", "\"\"\"", .string),
        .span("\"", "\"", .string, rules: [.match("\\\\.", .stringEscape)]),
        .span("\\{\\{", "\\}\\}", .code, rules: [.span("\\(", "\\)", .variable)]),
        .span("--", "$", .comment),
        .match("^#\\w+", .keyword),
        .words(["if", "else", "return"], .keyword),
        .match("\\b\\d+(?:\\.\\d+)?\\b", .number),
    ])

    /// Tokens as (text, scope) pairs, which read better in assertions than ranges.
    private func tokens(_ line: String, _ state: LineState = .initial, grammar: Grammar? = nil)
        -> (tokens: [Pair], endState: LineState) {
        let text = line as NSString
        let result = (grammar ?? self.grammar).tokenize(line: text, startingIn: state)
        return (result.tokens.map { Pair(text.substring(with: $0.range), $0.scope) }, result.endState)
    }

    struct Pair: Equatable, CustomStringConvertible {
        let text: String
        let scope: SyntaxScope
        init(_ text: String, _ scope: SyntaxScope) {
            self.text = text
            self.scope = scope
        }
        var description: String { "(\(String(reflecting: text)), \(scope))" }
    }

    func testKeywordsAndNumbers() {
        XCTAssertEqual(tokens("if x return 42 else 3.5").tokens, [
            Pair("if", .keyword), Pair("return", .keyword), Pair("42", .number),
            Pair("else", .keyword), Pair("3.5", .number),
        ])
        XCTAssertEqual(tokens("ifx elsewhere x42").tokens, [], "keywords and numbers need word boundaries")
    }

    func testLineCommentRunsToEndOfLine() {
        let result = tokens("x = 1 // if 2")
        XCTAssertEqual(result.tokens, [Pair("1", .number), Pair("// if 2", .comment)])
        XCTAssertEqual(result.endState, .initial)
    }

    func testStringWithEscapes() {
        XCTAssertEqual(tokens("\"a\\\"b\" if").tokens, [
            Pair("\"a", .string), Pair("\\\"", .stringEscape), Pair("b\"", .string), Pair("if", .keyword),
        ])
    }

    func testBlockCommentAcrossLines() {
        let first = tokens("a /* start if")
        XCTAssertEqual(first.tokens, [Pair("/* start if", .comment)])
        XCTAssertTrue(first.endState.isInsideSpan)

        let second = tokens("still 42", first.endState)
        XCTAssertEqual(second.tokens, [Pair("still 42", .comment)])
        XCTAssertEqual(second.endState, first.endState)

        let third = tokens("end */ if", second.endState)
        XCTAssertEqual(third.tokens, [Pair("end */", .comment), Pair("if", .keyword)])
        XCTAssertEqual(third.endState, .initial)
    }

    func testEmptyLineKeepsState() {
        let open = tokens("/*").endState
        let empty = tokens("", open)
        XCTAssertEqual(empty.tokens, [])
        XCTAssertEqual(empty.endState, open)
    }

    func testEarlierRuleWinsTies() {
        // `"""` and `"` both match at 0; the triple quote is listed first.
        let result = tokens("\"\"\"doc \" still")
        XCTAssertEqual(result.tokens, [Pair("\"\"\"doc \" still", .string)])
        XCTAssertTrue(result.endState.isInsideSpan)
    }

    func testCaretMeansStartOfLine() {
        XCTAssertEqual(tokens("#define x").tokens, [Pair("#define", .keyword)])
        XCTAssertEqual(tokens("x #define").tokens, [], "^ must not match where a search continues mid-line")
    }

    func testSpanEndingAtEndOfLine() {
        let result = tokens("a -- if b")
        XCTAssertEqual(result.tokens, [Pair("-- if b", .comment)])
        XCTAssertEqual(result.endState, .initial, "an end pattern of $ closes the span at the end of the line")
    }

    func testNestedSpans() {
        XCTAssertEqual(tokens("{{a (b) c}} 1").tokens, [
            Pair("{{a ", .code), Pair("(b)", .variable), Pair(" c}}", .code), Pair("1", .number),
        ])
    }

    func testRangesAreUTF16Offsets() {
        let line = "é😀 if \"ř\""
        let result = grammar.tokenize(line: line as NSString, startingIn: .initial)
        // "é" is 1 UTF-16 unit, "😀" is 2, then a space: "if" starts at 4.
        XCTAssertEqual(result.tokens.first, SyntaxToken(range: NSRange(location: 4, length: 2), scope: .keyword))
        XCTAssertEqual(tokens(line).tokens, [Pair("if", .keyword), Pair("\"ř\"", .string)])
    }

    func testRulesThatCanMatchEmptyTextDoNotHang() {
        let risky = Grammar(name: "Risky", rules: [.match("x*", .keyword), .match("\\d", .number)])
        XCTAssertEqual(tokens("ab1xx", grammar: risky).tokens, [Pair("1", .number), Pair("xx", .keyword)])
    }

    func testTokensAreOrderedAndDoNotOverlap() {
        let result = grammar.tokenize(line: "if \"a\\n\" /* x */ 1 {{ (y) }} // end" as NSString, startingIn: .initial)
        for (previous, next) in zip(result.tokens, result.tokens.dropFirst()) {
            XCTAssertLessThanOrEqual(NSMaxRange(previous.range), next.range.location)
        }
    }
}
