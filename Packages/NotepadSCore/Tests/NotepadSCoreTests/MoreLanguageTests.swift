import XCTest
@testable import NotepadSCore

/// Grammars added in v0.4.
final class MoreLanguageTests: XCTestCase {

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

    func testYAML() {
        XCTAssertEqual(tokens(.yaml, [
            "--- # config",
            "name: \"Café\\n\"  # comment",
            "- port: 8080",
            "  url: http://example.com/a#b",
            "enabled: true",
            "base: &base ~",
            "text: |",
        ]), [
            [Pair("---", .keyword), Pair("# config", .comment)],
            [Pair("name", .property), Pair("\"Café", .string), Pair("\\n", .stringEscape), Pair("\"", .string),
             Pair("# comment", .comment)],
            [Pair("-", .keyword), Pair("port", .property), Pair("8080", .number)],
            [Pair("url", .property)],
            [Pair("enabled", .property), Pair("true", .constant)],
            [Pair("base", .property), Pair("&base", .variable), Pair("~", .constant)],
            [Pair("text", .property), Pair("|", .keyword)],
        ])
    }

    func testJavaScript() {
        XCTAssertEqual(tokens(.javaScript, [
            "const greet = (name) => `Hi ${name}\\n`; // say hi",
            "if (count > 0x1F) { return null; }",
            "/* multi",
            "line */ fetchData(42n);",
        ]), [
            [Pair("const", .keyword), Pair("`Hi ", .string), Pair("${name}", .variable), Pair("\\n", .stringEscape),
             Pair("`", .string), Pair("// say hi", .comment)],
            [Pair("if", .keyword), Pair("0x1F", .number), Pair("return", .keyword), Pair("null", .constant)],
            [Pair("/* multi", .comment)],
            [Pair("line */", .comment), Pair("fetchData", .function), Pair("42n", .number)],
        ])
    }

    func testTypeScriptAddsTypeKeywords() {
        XCTAssertEqual(tokens(.typeScript, ["interface User { name: string }"]),
                       [[Pair("interface", .keyword), Pair("string", .keyword)]])
        XCTAssertEqual(tokens(.javaScript, ["interface User { name: string }"]), [[]],
                       "plain JavaScript doesn't know these words")
    }

    func testC() {
        XCTAssertEqual(tokens(.c, [
            "#include <stdio.h>",
            "int main(void) { printf(\"%d\\n\", 'x'); return 0x10u; } // done",
        ]), [
            [Pair("#include", .keyword), Pair(" <stdio.h>", .string)],
            [Pair("int", .keyword), Pair("main", .function), Pair("void", .keyword), Pair("printf", .function),
             Pair("\"%d", .string), Pair("\\n", .stringEscape), Pair("\"", .string), Pair("'x'", .string),
             Pair("return", .keyword), Pair("0x10u", .number), Pair("// done", .comment)],
        ])
    }

    func testCppAddsKeywords() {
        XCTAssertEqual(tokens(.cpp, ["template <typename T> class Box { public: T* p = nullptr; };"]), [[
            Pair("template", .keyword), Pair("typename", .keyword), Pair("class", .keyword),
            Pair("public", .keyword), Pair("nullptr", .constant),
        ]])
    }

    func testHTML() {
        XCTAssertEqual(tokens(.html, [
            "<!DOCTYPE html>",
            "<a href=\"/x\" class='y'>Caf&eacute;</a> <!-- note -->",
            "<img",
            "  src=\"a.png\" />",
        ]), [
            [Pair("<!DOCTYPE html>", .keyword)],
            [Pair("<a ", .keyword), Pair("href", .property), Pair("=", .keyword), Pair("\"/x\"", .string),
             Pair(" ", .keyword), Pair("class", .property), Pair("=", .keyword), Pair("'y'", .string),
             Pair(">", .keyword), Pair("&eacute;", .constant), Pair("</a>", .keyword), Pair("<!-- note -->", .comment)],
            [Pair("<img", .keyword)],
            [Pair("  ", .keyword), Pair("src", .property), Pair("=", .keyword), Pair("\"a.png\"", .string),
             Pair(" />", .keyword)],
        ])
    }

    func testXML() {
        XCTAssertEqual(tokens(.xml, [
            "<?xml version=\"1.0\"?>",
            "<key>a</key><![CDATA[<raw>]]>",
        ]), [
            [Pair("<?xml ", .keyword), Pair("version", .property), Pair("=", .keyword), Pair("\"1.0\"", .string),
             Pair("?>", .keyword)],
            [Pair("<key>", .keyword), Pair("</key>", .keyword), Pair("<![CDATA[<raw>]]>", .code)],
        ])
    }

    func testDetection() {
        let cases: [(String, Language)] = [
            ("docker-compose.yml", .yaml), ("app.mjs", .javaScript), ("App.tsx", .typeScript),
            ("main.c", .c), ("lib.h", .c), ("main.cpp", .cpp), ("index.html", .html),
            ("Info.plist", .xml), ("icon.svg", .xml), ("MainMenu.xib", .xml),
        ]
        for (name, language) in cases {
            XCTAssertEqual(Language.detect(fileName: name, firstLine: nil), language, name)
        }
        XCTAssertEqual(Language.detect(fileName: "server", firstLine: "#!/usr/bin/env node"), .javaScript)
    }

    func testNewGrammarsHandleAwkwardInput() {
        let lines = ["", "\"", "'", "`", "<", "<!--", "/*", "#", "😀 é", String(repeating: "<a ", count: 2_000)]
        for grammar in [Grammar.yaml, .javaScript, .typeScript, .c, .cpp, .html, .xml] {
            _ = tokens(grammar, lines)   // must terminate without crashing
        }
    }
}
