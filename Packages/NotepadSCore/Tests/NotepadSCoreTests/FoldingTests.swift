import XCTest
@testable import NotepadSCore

final class FoldingTests: XCTestCase {

    /// Regions as "first-last: hidden text" (1-based lines).
    private func regions(_ text: String, _ language: Language) -> [String] {
        let string = text as NSString
        return Folding.regions(in: string, lineIndex: LineIndex(text: string), language: language).map {
            "\($0.startLine + 1)-\($0.endLine + 1): \(string.substring(with: $0.hiddenRange).debugDescription)"
        }
    }

    func testBracesHideTheInsideAndNest() {
        let text = "func a() {\n    if x {\n        y()\n    }\n}\nfunc b() { one() }\n"
        XCTAssertEqual(regions(text, .swift), [
            #"1-5: "\n    if x {\n        y()\n    }\n""#,
            #"2-4: "\n        y()\n    ""#,
        ])
    }

    func testBracesInCommentsAndStringsDontCount() {
        let text = "int main() {\n    // }\n    s = \"{\";\n    /* {\n    } */\n}"
        XCTAssertEqual(regions(text, .c), [#"1-6: "\n    // }\n    s = \"{\";\n    /* {\n    } */\n""#])
    }

    func testElseLinesCloseAndOpenAndCRLFStays() {
        let text = "if (a) {\r\n  x();\r\n} else {\r\n  y();\r\n}"
        XCTAssertEqual(regions(text, .javaScript), [#"1-3: "\r\n  x();\r\n""#, #"3-5: "\r\n  y();\r\n""#])
    }

    func testJSONFoldsBracketsToo() {
        XCTAssertEqual(regions("{\n  \"a\": [\n    1\n  ]\n}", .json), [#"1-5: "\n  \"a\": [\n    1\n  ]\n""#, #"2-4: "\n    1\n  ""#])
    }

    func testUnbalancedBracesDontCrash() {
        XCTAssertEqual(regions("}\n{\n x", .c), [])
    }

    func testIndentationBlocksSkipTrailingBlankLines() {
        let text = "class A:\n    def f(self):\n        pass\n\n    x = 1\n\ndef g():\n\tpass\n"
        XCTAssertEqual(regions(text, .python), [
            #"1-5: "\n    def f(self):\n        pass\n\n    x = 1""#,
            #"2-3: "\n        pass""#,
            #"7-8: "\n\tpass""#,
        ])
    }

    func testMarkdownHeadingsFoldUntilTheNextSameLevelHeading() {
        let text = "# Title\nIntro\n## Part\nText é 😀\n\n## Next\nMore\n```\n# code\n```\n"
        XCTAssertEqual(regions(text, .markdown), [
            #"1-10: "\nIntro\n## Part\nText é 😀\n\n## Next\nMore\n```\n# code\n```""#,
            #"3-4: "\nText é 😀""#,
            #"6-10: "\nMore\n```\n# code\n```""#,
        ])
    }

    func testPlainTextDoesntFold() {
        XCTAssertEqual(regions("a\n    b\n", .plainText), [])
    }
}
