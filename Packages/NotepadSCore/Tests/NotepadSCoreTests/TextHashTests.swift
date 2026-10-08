import XCTest
@testable import NotepadSCore

final class TextHashTests: XCTestCase {

    /// Known digests of "abc" (FIPS 180 / RFC 1321 test vectors) and of empty input.
    func testKnownVectors() {
        let abc = Data("abc".utf8)
        XCTAssertEqual(TextHash.sha256.hexDigest(of: abc), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(TextHash.sha512.hexDigest(of: abc),
                       "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        XCTAssertEqual(TextHash.sha1.hexDigest(of: abc), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(TextHash.md5.hexDigest(of: abc), "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(TextHash.sha256.hexDigest(of: Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(TextHash.sha512.hexDigest(of: Data()),
                       "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
        XCTAssertEqual(TextHash.md5.hexDigest(of: Data()), "d41d8cd98f00b204e9800998ecf8427e")
    }

    /// The whole-document hash is over the bytes Save writes, so the encoding and the line
    /// breaks matter: the same text in Windows-1252 with CRLF hashes differently than UTF-8 with LF.
    func testDocumentHashUsesSavedBytes() throws {
        let utf8 = try TextFile.encode("Café\n", encoding: .utf8)
        let windows = try TextFile.encode("Café\r\n", encoding: .windows1252)
        XCTAssertNotEqual(TextHash.sha256.hexDigest(of: utf8), TextHash.sha256.hexDigest(of: windows))
        XCTAssertEqual(TextHash.md5.hexDigest(of: windows), TextHash.md5.hexDigest(of: Data([0x43, 0x61, 0x66, 0xE9, 0x0D, 0x0A])))
    }

    func testNames() {
        XCTAssertEqual(TextHash.allCases.map(\.name), ["SHA-256", "SHA-512", "SHA-1", "MD5"])
    }
}
