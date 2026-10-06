import XCTest
@testable import NotepadSCore

final class CodecTests: XCTestCase {

    private func apply(_ transform: TextTransform, _ text: String, lineEnding: LineEnding = .lf) throws -> String {
        try transform.apply(to: text, context: TransformContext(lineEnding: lineEnding))
    }

    /// RFC 4648 §10 test vectors.
    func testBase64Vectors() throws {
        let vectors = ["": "", "f": "Zg==", "fo": "Zm8=", "foo": "Zm9v", "foob": "Zm9vYg==",
                       "fooba": "Zm9vYmE=", "foobar": "Zm9vYmFy"]
        for (plain, encoded) in vectors {
            XCTAssertEqual(try apply(.base64Encode, plain), encoded)
            XCTAssertEqual(try apply(.base64Decode, encoded), plain)
        }
    }

    func testBase64UsesUTF8AndKeepsLineBreaksAsStored() throws {
        XCTAssertEqual(try apply(.base64Encode, "é😀"), "w6nwn5iA")
        XCTAssertEqual(try apply(.base64Encode, "a\r\nb"), "YQ0KYg==")
    }

    func testBase64DecodeIsLenient() throws {
        XCTAssertEqual(try apply(.base64Decode, "Zm9v\nYmFy\r\n"), "foobar", "line-wrapped input")
        XCTAssertEqual(try apply(.base64Decode, "Zg"), "f", "missing padding")
        XCTAssertEqual(try apply(.base64Decode, "Pz8-"), "??>", "URL-safe alphabet (standard: Pz8+)")
        XCTAssertEqual(try apply(.base64Decode, "Pz8_"), "???", "URL-safe alphabet (standard: Pz8/)")
    }

    func testBase64DecodedLineBreaksGetTheDocumentStyle() throws {
        XCTAssertEqual(try apply(.base64Decode, "YQpi", lineEnding: .crlf), "a\r\nb")   // "a\nb"
    }

    func testBase64DecodeErrors() {
        XCTAssertThrowsError(try apply(.base64Decode, "not base64!"))
        XCTAssertThrowsError(try apply(.base64Decode, "/w=="), "byte 0xFF isn't UTF-8 text")
    }

    func testURLEncode() throws {
        XCTAssertEqual(try apply(.urlEncode, "a b&c=d/é?x#y+z"), "a%20b%26c%3Dd%2F%C3%A9%3Fx%23y%2Bz")
        XCTAssertEqual(try apply(.urlEncode, "AZaz09-._~"), "AZaz09-._~", "RFC 3986 unreserved characters stay")
        XCTAssertEqual(try apply(.urlEncode, "😀\n"), "%F0%9F%98%80%0A")
    }

    func testURLDecode() throws {
        XCTAssertEqual(try apply(.urlDecode, "a%20b%26c%3Dd%2F%C3%A9"), "a b&c=d/é")
        XCTAssertEqual(try apply(.urlDecode, "a+b"), "a+b", "+ is only a space in HTML forms, not in URLs")
        XCTAssertEqual(try apply(.urlDecode, "x%0D%0Ay", lineEnding: .lf), "x\ny")
        XCTAssertThrowsError(try apply(.urlDecode, "%E9"), "Latin-1 byte, not UTF-8")
        XCTAssertThrowsError(try apply(.urlDecode, "100%"), "incomplete escape")
    }

    func testEncodeDecodeRoundTrip() throws {
        let text = "Café naïve façade\tjalapeño 😀"
        XCTAssertEqual(try apply(.base64Decode, try apply(.base64Encode, text)), text)
        XCTAssertEqual(try apply(.urlDecode, try apply(.urlEncode, text)), text)
    }
}
