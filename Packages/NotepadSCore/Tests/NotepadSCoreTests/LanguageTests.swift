import XCTest
@testable import NotepadSCore

final class LanguageTests: XCTestCase {

    private typealias Pair = TokenizerTests.Pair

    /// Tokenizes `lines` in order, carrying the state; returns the tokens of each line.
    private func tokens(_ grammar: Grammar, _ lines: [String]) -> [[Pair]] {
        var state = LineState.initial
        return lines.map { line in
            let text = line as NSString
            let result = grammar.tokenize(line: text, startingIn: state)
            state = result.endState
            return result.tokens.map { Pair(text.substring(with: $0.range), $0.scope) }
        }
    }

    // MARK: - Grammars

    func testJSON() {
        XCTAssertEqual(tokens(.json, [#"{"name": "Café \"x\" \u00e9", "n": -1.5e3, "ok": true, "x": null}"#]), [[
            Pair(#""name""#, .property), Pair(#""Café "#, .string), Pair(#"\""#, .stringEscape), Pair("x", .string),
            Pair(#"\""#, .stringEscape), Pair(" ", .string), Pair(#"\u00e9"#, .stringEscape), Pair(#"""#, .string),
            Pair(#""n""#, .property), Pair("-1.5e3", .number), Pair(#""ok""#, .property), Pair("true", .constant),
            Pair(#""x""#, .property), Pair("null", .constant),
        ]])
        // An unterminated string doesn't leak into the next line.
        XCTAssertEqual(tokens(.json, [#""open"#, "1"]), [[Pair(#""open"#, .string)], [Pair("1", .number)]])
    }

    func testPython() {
        XCTAssertEqual(tokens(.python, [
            "@dataclass",
            "def greet(name='é'):  # say hi",
            #"    return f"Hi {name}\n" if name is not None else 0x1F"#,
            #"text = """first"#,
            "still in the string",
            #"end""" + rb'raw'"#,
        ]), [
            [Pair("@dataclass", .function)],
            [Pair("def", .keyword), Pair("greet", .function), Pair("'é'", .string), Pair("# say hi", .comment)],
            [Pair("return", .keyword), Pair(#"f"Hi {name}"#, .string), Pair(#"\n"#, .stringEscape), Pair(#"""#, .string),
             Pair("if", .keyword), Pair("is", .keyword), Pair("not", .keyword), Pair("None", .constant),
             Pair("else", .keyword), Pair("0x1F", .number)],
            [Pair(#""""first"#, .string)],
            [Pair("still in the string", .string)],
            [Pair(#"end""""#, .string), Pair("rb'raw'", .string)],
        ])
    }

    func testShell() {
        XCTAssertEqual(tokens(.shell, [
            "#!/bin/bash",
            #"if [ "$HOME" != '$NOT' ]; then echo ${USER:-x} $1 # done"#,
            "echo a#b $#",
        ]), [
            [Pair("#!/bin/bash", .comment)],
            [Pair("if", .keyword), Pair(#"""#, .string), Pair("$HOME", .variable), Pair(#"""#, .string),
             Pair("'$NOT'", .string), Pair("then", .keyword), Pair("${USER:-x}", .variable), Pair("$1", .variable),
             Pair("# done", .comment)],
            [Pair("$#", .variable)],
        ])
    }

    func testMarkdown() {
        XCTAssertEqual(tokens(.markdown, [
            "# Title",
            "Some *emphasis*, **strong**, `code` and [a link](https://example.com).",
            "- item",
            "```swift",
            "let x = \"# not a heading\"",
            "```",
            "#hashtag is not a heading",
        ]), [
            [Pair("# Title", .heading)],
            [Pair("*emphasis*", .emphasis), Pair("**strong**", .strong), Pair("`code`", .code),
             Pair("[a link](https://example.com)", .link)],
            [Pair("-", .keyword)],
            [Pair("```swift", .code)],
            [Pair("let x = \"# not a heading\"", .code)],
            [Pair("```", .code)],
            [],
        ])
    }

    func testEveryGrammarHandlesAwkwardInput() {
        let lines = ["", "\"", "'''", "/*", "😀 é ř", "\\", "```", String(repeating: "x", count: 5_000)]
        for language in Language.allCases {
            guard let grammar = language.grammar else { continue }
            _ = tokens(grammar, lines)   // must terminate without crashing
        }
    }

    // MARK: - Detection

    func testDetectionByFileName() {
        XCTAssertEqual(Language.detect(fileName: "package.json", firstLine: nil), .json)
        XCTAssertEqual(Language.detect(fileName: "README.MD", firstLine: nil), .markdown)
        XCTAssertEqual(Language.detect(fileName: "setup.py", firstLine: "#!/bin/bash"), .python, "extension wins")
        XCTAssertEqual(Language.detect(fileName: ".zshrc", firstLine: nil), .shell)
        XCTAssertEqual(Language.detect(fileName: "deploy.sh", firstLine: nil), .shell)
        XCTAssertEqual(Language.detect(fileName: "notes.txt", firstLine: nil), .plainText)
        XCTAssertEqual(Language.detect(fileName: "LICENSE", firstLine: nil), .plainText)
    }

    func testDetectionByShebang() {
        XCTAssertEqual(Language.detect(fileName: "deploy", firstLine: "#!/bin/bash"), .shell)
        XCTAssertEqual(Language.detect(fileName: nil, firstLine: "#!/usr/bin/env python3"), .python)
        XCTAssertEqual(Language.detect(fileName: nil, firstLine: "#!/usr/bin/env -S zsh -f"), .shell)
        XCTAssertEqual(Language.detect(fileName: nil, firstLine: "#!/usr/bin/env perl"), .plainText)
        XCTAssertEqual(Language.detect(fileName: nil, firstLine: "# comment"), .plainText)
        XCTAssertEqual(Language.detect(fileName: nil, firstLine: "#!"), .plainText)
    }

    func testNames() {
        XCTAssertEqual(Language.plainText.displayName, "Plain Text")
        XCTAssertEqual(Language.json.displayName, Grammar.json.name)
    }
}
