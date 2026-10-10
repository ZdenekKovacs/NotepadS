import XCTest
@testable import NotepadSCore

final class FunctionListTests: XCTestCase {

    /// The symbols as "name@line" (1-based), with two spaces per depth.
    private func list(_ text: String, _ language: Language) -> [String] {
        let string = text as NSString
        return FunctionList.symbols(in: string, lineIndex: LineIndex(text: string), language: language)
            .map { String(repeating: "  ", count: $0.depth) + "\($0.name)@\($0.line + 1)" }
    }

    func testSwift() {
        let text = """
        import Foundation
        /// func notThis()
        final class Editor: NSObject {
            private static func make() -> Editor { Editor() }
            init(name: String) {}
            let s = "func alsoNotThis()"
        }
        extension Editor.Kind {
            func run() async throws {}
        }
        """
        XCTAssertEqual(list(text, .swift), ["Editor@3", "  make@4", "  init@5", "Editor.Kind@8", "  run@9"])
    }

    func testPython() {
        let text = "class Shape:\r\n    def area(self):\r\n        pass\r\n\r\n'''\r\ndef inDocstring():\r\n'''\r\nasync def main():\r\n    pass"
        XCTAssertEqual(list(text, .python), ["Shape@1", "  area@2", "main@8"])
    }

    func testJavaScript() {
        let text = """
        function hello(a) {
        }
        export const add = (a, b) => a + b;
        const sub = async function () {}
        class Point {
          constructor(x) {
          }
          static origin() {
          }
          if (x) {
          }
        }
        // function commented() {}
        """
        XCTAssertEqual(list(text, .javaScript), ["hello@1", "add@3", "sub@4", "Point@5", "  constructor@6", "  origin@8"])
    }

    func testCAndJava() {
        let c = """
        #include <stdio.h>
        static int add(int a, int b)
        {
            return add(a, b);
        }
        struct point {
            int x;
        };
        int main(int argc, char **argv) {
            if (argc > 1) {
                printf("x");
            }
        }
        """
        XCTAssertEqual(list(c, .c), ["add@2", "point@6", "main@9"])

        let java = """
        public class App {
            public static void main(String[] args) {
                System.out.println("x");
            }
            private List<String> names() {
                return List.of();
            }
        }
        """
        XCTAssertEqual(list(java, .java), ["App@1", "  main@2", "  names@5"])
    }

    func testGoRustAndShell() {
        XCTAssertEqual(list("type Server struct {\n}\nfunc (s *Server) Run() error {\n}\nfunc main() {}", .go),
                       ["Server@1", "Run@3", "main@5"])
        XCTAssertEqual(list("pub struct Point;\nimpl Point {\n    pub fn new() -> Self {}\n}", .rust),
                       ["Point@1", "Point@2", "  new@3"])
        XCTAssertEqual(list("#!/bin/sh\nbuild() {\n  :\n}\nfunction deploy {\n}\n# fake() {", .shell), ["build@2", "deploy@5"])
    }

    func testMarkdownHeadingsNestByLevelAndSkipCode() {
        let text = "# Title\nText\n## Part *one*\n```\n# not a heading\n```\n### Détail 😀\n## Two"
        XCTAssertEqual(list(text, .markdown), ["Title@1", "  Part *one*@3", "    Détail 😀@7", "  Two@8"])
    }

    func testSectionsAndTargets() {
        XCTAssertEqual(list("[server]\nport=1\n[client]", .ini), ["server@1", "client@3"])
        XCTAssertEqual(list("all: build\nCC := gcc\nbuild:\n\tcc main.c", .makefile), ["all@1", "build@3"])
    }

    func testNameRangePointsIntoTheText() throws {
        let text = "x\r\ndef été():\n    pass" as NSString
        let symbol = try XCTUnwrap(FunctionList.symbols(in: text, lineIndex: LineIndex(text: text), language: .python).first)
        XCTAssertEqual(text.substring(with: symbol.range), "été")
    }

    func testLanguagesWithoutRulesAndEmptyText() {
        XCTAssertEqual(list("{\"a\": 1}", .json), [])
        XCTAssertEqual(list("", .swift), [])
        XCTAssertEqual(list("just text", .plainText), [])
    }

    func testEveryLanguagesPatternsCompile() {
        for language in Language.allCases {
            _ = language.symbolRules   // a bad pattern stops with a precondition failure
        }
    }
}
