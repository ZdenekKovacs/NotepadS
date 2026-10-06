import XCTest
@testable import NotepadSCore

/// Grammars added after v0.4.
final class ExtraLanguageTests: XCTestCase {

    private typealias Pair = TokenizerTests.Pair

    private func tokens(_ grammar: Grammar, _ lines: [String]) -> [[Pair]] {
        var state = LineState.initial
        return lines.map { line in
            let text = line as NSString
            let result = grammar.tokenize(line: text, startingIn: state)
            state = result.endState
            return result.tokens.map { Pair(text.substring(with: $0.range), $0.scope) }
        }
    }

    func testCSS() {
        XCTAssertEqual(tokens(.css, ["a:hover { color: #fff; margin: 0 1.5em !important; } /* x */"]), [[
            Pair("color", .property), Pair("#fff", .number), Pair("margin", .property), Pair("0", .number),
            Pair("1.5em", .number), Pair("!important", .keyword), Pair("/* x */", .comment),
        ]])
        XCTAssertEqual(tokens(.css, ["@media (width > 600px) { --gap: calc(2px); }"]), [[
            Pair("@media", .keyword), Pair("600px", .number), Pair("--gap", .variable), Pair("calc", .function),
            Pair("2px", .number),
        ]])
    }

    func testSQLKeywordsInAnyCase() {
        XCTAssertEqual(tokens(.sql, ["select name, COUNT(*) From users WHERE note = 'it''s' AND id > 10 -- all"]), [[
            Pair("select", .keyword), Pair("COUNT", .function), Pair("From", .keyword), Pair("WHERE", .keyword),
            Pair("'it", .string), Pair("''", .stringEscape), Pair("s'", .string), Pair("AND", .keyword),
            Pair("10", .number), Pair("-- all", .comment),
        ]])
    }

    func testSwift() {
        XCTAssertEqual(tokens(.swift, [#"@MainActor func greet(_ name: String) -> String { return "Hi \(name)!" } // x"#]), [[
            Pair("@MainActor", .function), Pair("func", .keyword), Pair("greet", .function), Pair("return", .keyword),
            Pair(#""Hi "#, .string), Pair(#"\(name)"#, .variable), Pair(#"!""#, .string), Pair("// x", .comment),
        ]])
    }

    func testJavaGoRust() {
        XCTAssertEqual(tokens(.java, [#"@Override public int size() { return 42L; }"#]), [[
            Pair("@Override", .function), Pair("public", .keyword), Pair("int", .keyword), Pair("size", .function),
            Pair("return", .keyword), Pair("42L", .number),
        ]])
        XCTAssertEqual(tokens(.go, ["func main() { fmt.Println(`raw`, nil) }"]), [[
            Pair("func", .keyword), Pair("main", .function), Pair("Println", .function), Pair("`raw`", .string),
            Pair("nil", .constant),
        ]])
        XCTAssertEqual(tokens(.rust, [#"fn first<'a>(s: &'a str) -> Option<char> { println!("{}", 'x'); None }"#]), [[
            Pair("fn", .keyword), Pair("first", .function), Pair("'a", .variable), Pair("'a", .variable),
            Pair("str", .keyword), Pair("char", .keyword), Pair("println!", .function), Pair(#""{}""#, .string),
            Pair("'x'", .string), Pair("None", .constant),
        ]])
    }

    func testPHPAndRuby() {
        XCTAssertEqual(tokens(.php, [#"<?php echo "Hi $name"; // x"#]), [[
            Pair("<?php", .keyword), Pair("echo", .keyword), Pair(#""Hi "#, .string), Pair("$name", .variable),
            Pair(#"""#, .string), Pair("// x", .comment),
        ]])
        XCTAssertEqual(tokens(.ruby, [#"def greet(name) = puts "Hi #{name}", :ok # x"#]), [[
            Pair("def", .keyword), Pair("greet", .function), Pair(#""Hi "#, .string), Pair("#{name}", .variable),
            Pair(#"""#, .string), Pair(":ok", .constant), Pair("# x", .comment),
        ]])
    }

    func testConfigFormats() {
        XCTAssertEqual(tokens(.toml, ["[package]", #"name = "notepads" # x"#, "version = 1.0"]), [
            [Pair("[package]", .keyword)],
            [Pair("name", .property), Pair(#""notepads""#, .string), Pair("# x", .comment)],
            [Pair("version", .property), Pair("1.0", .number)],
        ])
        XCTAssertEqual(tokens(.ini, ["; comment", "[core]", "editor = vim", "autocrlf = true"]), [
            [Pair("; comment", .comment)], [Pair("[core]", .keyword)], [Pair("editor", .property)],
            [Pair("autocrlf", .property), Pair("true", .constant)],
        ])
    }

    func testBuildFiles() {
        XCTAssertEqual(tokens(.makefile, ["CC ?= clang # compiler", "build: main.o", "\t$(CC) -o $@ $<"]), [
            [Pair("CC", .property), Pair("# compiler", .comment)],
            [Pair("build", .function)],
            [Pair("$(CC)", .variable), Pair("$@", .variable), Pair("$<", .variable)],
        ])
        XCTAssertEqual(tokens(.dockerfile, ["FROM swift:6 AS build", #"RUN echo "$HOME" # x"#]), [
            [Pair("FROM", .keyword), Pair("AS", .keyword)],
            [Pair("RUN", .keyword), Pair(#"""#, .string), Pair("$HOME", .variable), Pair(#"""#, .string)],
        ])
    }

    func testDiff() {
        XCTAssertEqual(tokens(.diff, ["--- a/x.txt", "+++ b/x.txt", "@@ -1,2 +1,2 @@ title", " same", "-old", "+new"]), [
            [Pair("--- a/x.txt", .keyword)], [Pair("+++ b/x.txt", .keyword)], [Pair("@@ -1,2 +1,2 @@", .function)],
            [], [Pair("-old", .deleted)], [Pair("+new", .inserted)],
        ])
    }

    func testDetection() {
        let cases: [(String, Language)] = [
            ("style.scss", .css), ("schema.sql", .sql), ("App.swift", .swift), ("Main.java", .java),
            ("main.go", .go), ("lib.rs", .rust), ("index.php", .php), ("app.rb", .ruby), ("Gemfile", .ruby),
            ("Cargo.toml", .toml), ("setup.cfg", .ini), (".editorconfig", .ini), ("Makefile", .makefile),
            ("Dockerfile", .dockerfile), ("fix.patch", .diff),
        ]
        for (name, language) in cases {
            XCTAssertEqual(Language.detect(fileName: name, firstLine: nil), language, name)
        }
        XCTAssertEqual(Language.detect(fileName: "tool", firstLine: "#!/usr/bin/env ruby"), .ruby)
    }

    func testEveryGrammarHandlesAwkwardInput() {
        let lines = ["", "\"", "'", "`", "/*", "#", "--", "=begin", "<?php", "😀 é", "\\",
                     String(repeating: "a: 'b' ", count: 1_000)]
        for language in Language.allCases {
            guard let grammar = language.grammar else { continue }
            _ = tokens(grammar, lines)   // must terminate without crashing
        }
    }
}
