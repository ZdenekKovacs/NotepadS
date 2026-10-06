import XCTest
@testable import NotepadSCore

final class CaseConversionTests: XCTestCase {

    private func apply(_ transform: TextTransform, _ text: String) throws -> String {
        try transform.apply(to: text, context: TransformContext(lineEnding: .lf, locale: Locale(identifier: "en_US")))
    }

    func testUpperLowerTitle() throws {
        XCTAssertEqual(try apply(.uppercase, "straße café ñ"), "STRASSE CAFÉ Ñ")
        XCTAssertEqual(try apply(.lowercase, "ÉCOLE Ñandú"), "école ñandú")
        XCTAssertEqual(try apply(.titleCase, "hello wORLD, crème brûlée"), "Hello World, Crème Brûlée")
    }

    func testCaseChangesKeepLineBreaks() throws {
        XCTAssertEqual(try apply(.uppercase, "a\r\nb\rc\n"), "A\r\nB\rC\n")
    }

    func testWordSplitting() {
        let cases: [String: [String]] = [
            "HTTPServer": ["HTTP", "Server"],
            "getHTTPResponse2Code": ["get", "HTTP", "Response2", "Code"],
            "XMLHttpRequest": ["XML", "Http", "Request"],
            "utf8String": ["utf8", "String"],
            "hello world-foo_bar.baz": ["hello", "world", "foo", "bar", "baz"],
            "ÉcoleNormale": ["École", "Normale"],
            "ABC": ["ABC"],
            "___": [],
        ]
        for (input, words) in cases {
            XCTAssertEqual(CaseConversion.splitIntoWords(ArraySlice(Array(input))), words, input)
        }
    }

    func testSnakeKebabCamel() throws {
        XCTAssertEqual(try apply(.snakeCase, "HTTPServer"), "http_server")
        XCTAssertEqual(try apply(.snakeCase, "getHTTPResponseCode"), "get_http_response_code")
        XCTAssertEqual(try apply(.kebabCase, "Hello World"), "hello-world")
        XCTAssertEqual(try apply(.camelCase, "http_server"), "httpServer")
        XCTAssertEqual(try apply(.camelCase, "user-ID number"), "userIdNumber")
        XCTAssertEqual(try apply(.snakeCase, "crème brûlée"), "crème_brûlée")
        XCTAssertEqual(try apply(.camelCase, "école normale"), "écoleNormale")
    }

    func testIdentifierStylesWorkPerLineAndKeepIndentation() throws {
        XCTAssertEqual(try apply(.snakeCase, "  firstName\t\r\n    lastName\r\n\n---\nZip"),
                       "  first_name\t\r\n    last_name\r\n\n---\nzip")
    }
}
