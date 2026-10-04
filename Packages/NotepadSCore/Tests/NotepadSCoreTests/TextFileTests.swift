import XCTest
@testable import NotepadSCore

final class TextEncodingTests: XCTestCase {

    private let western = "Café naïve façade, jalapeño, smörgåsbord, Straße. CAFÉ NAÏVE FAÇADE. “Quotes” — €5"

    func testSingleByteTablesAreOneToOne() {
        for table in [SingleByteTable.windows1252, .isoLatin1] {
            XCTAssertEqual(table.scalarForByte.count, 256)
            XCTAssertEqual(Set(table.scalarForByte.map(\.value)).count, 256)
            XCTAssertEqual(table.byteForScalar.count, 256)
        }
    }

    func testKnownWesternBytes() throws {
        // Windows-1252: € = 0x80, “ = 0x93, ” = 0x94, — = 0x97, é = 0xE9, ß = 0xDF.
        XCTAssertEqual(try TextFile.encode("€“”—éß", encoding: .windows1252),
                       Data([0x80, 0x93, 0x94, 0x97, 0xE9, 0xDF]))
        // ISO-8859-1 is Unicode U+0000–U+00FF byte for byte.
        XCTAssertEqual(try TextFile.encode("éßÿ\u{A0}", encoding: .isoLatin1), Data([0xE9, 0xDF, 0xFF, 0xA0]))
    }

    func testEveryByteRoundTripsInSingleByteEncodings() throws {
        let allBytes = Data((0...255).map { UInt8($0) })
        for encoding in [TextEncoding.windows1252, .isoLatin1] {
            let text = try XCTUnwrap(encoding.decode(allBytes))
            XCTAssertEqual(encoding.encode(text), allBytes, "\(encoding)")
        }
    }

    func testCanEncode() {
        XCTAssertTrue(TextEncoding.windows1252.canEncode(western))
        XCTAssertFalse(TextEncoding.windows1252.canEncode("hello 😀"))
        XCTAssertFalse(TextEncoding.windows1252.canEncode("Příliš"))     // Central European letters
        XCTAssertFalse(TextEncoding.isoLatin1.canEncode("€"))           // € exists only in Windows-1252
        XCTAssertTrue(TextEncoding.isoLatin1.canEncode("Café naïve façade"))
        XCTAssertTrue(TextEncoding.utf8.canEncode("😀"))
        // Decomposed "é" (e + combining accent) is not a single Windows-1252 byte.
        XCTAssertFalse(TextEncoding.windows1252.canEncode("e\u{301}"))
    }

    /// The names come from the package's String Catalog; English is the source language.
    func testLocalizedNamesResolve() {
        XCTAssertEqual(TextEncoding.windows1252.displayName, "Western (Windows-1252)")
        XCTAssertEqual(LineEnding.crlf.displayName, "CRLF (Windows)")
        XCTAssertEqual(TextCodecError.binaryFile.errorDescription, "The file doesn’t contain plain text.")
    }

    func testFirstUnencodableCharacter() throws {
        let found = try XCTUnwrap(TextEncoding.windows1252.firstUnencodableCharacter(in: "é\r\nñ\r😀x"))
        XCTAssertEqual(found.character, "😀")
        XCTAssertEqual(found.line, 3)
        XCTAssertEqual(found.utf16Offset, 5)
        XCTAssertNil(TextEncoding.windows1252.firstUnencodableCharacter(in: western))
        XCTAssertNil(TextEncoding.utf8.firstUnencodableCharacter(in: "😀"))
    }
}

final class EncodingDetectorTests: XCTestCase {

    func testByteOrderMarks() throws {
        XCTAssertEqual(try EncodingDetector.detect(Data([0xEF, 0xBB, 0xBF, 0x61])), .utf8WithBOM)
        XCTAssertEqual(try EncodingDetector.detect(Data([0xFF, 0xFE, 0x61, 0x00])), .utf16LittleEndian)
        XCTAssertEqual(try EncodingDetector.detect(Data([0xFE, 0xFF, 0x00, 0x61])), .utf16BigEndian)
    }

    func testUTF8AndASCII() throws {
        XCTAssertEqual(try EncodingDetector.detect(Data("plain ascii".utf8)), .utf8)
        XCTAssertEqual(try EncodingDetector.detect(Data("café naïve 😀".utf8)), .utf8)
        XCTAssertEqual(try EncodingDetector.detect(Data()), .utf8)
    }

    func testWindows1252() throws {
        let data = try TextFile.encode("“Café” — €5", encoding: .windows1252)
        XCTAssertEqual(try EncodingDetector.detect(data), .windows1252)
    }

    func testLatin1TextIsReadAsWindows1252AndStaysByteExact() throws {
        let data = try TextFile.encode("Café naïve façade", encoding: .isoLatin1)
        XCTAssertEqual(try EncodingDetector.detect(data), .windows1252)
        let decoded = try TextFile.decode(data)
        XCTAssertEqual(decoded.text, "Café naïve façade")
        XCTAssertEqual(try TextFile.encode(decoded.text, encoding: decoded.encoding), data)
    }

    func testBinary() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        XCTAssertThrowsError(try EncodingDetector.detect(png)) { error in
            XCTAssertEqual(error as? TextCodecError, .binaryFile)
        }
    }
}

final class TextFileTests: XCTestCase {

    private let samples = [
        "a\nb\nc\n",
        "Café\r\nnaïve\r\nfaçade",
        "jalapeño\rsmörgåsbord\rStraße\r",
        "mixed\r\nlines\nand\rbreaks\r\n\r\n\n",
        "",
    ]

    /// Opening and saving without edits must reproduce the file byte for byte.
    func testDecodeEncodeIsByteExactInEveryEncoding() throws {
        for encoding in TextEncoding.allCases {
            for sample in samples {
                let bytes = try TextFile.encode(sample, encoding: encoding)
                let decoded = try TextFile.decode(bytes)
                XCTAssertEqual(decoded.text, sample, "\(encoding)")
                // Without a BOM an ISO-8859-1 file is detected as Windows-1252; force it.
                let forced = try TextFile.decode(bytes, encoding: encoding)
                XCTAssertEqual(forced.encoding, encoding)
                XCTAssertEqual(try TextFile.encode(forced.text, encoding: forced.encoding), bytes, "\(encoding)")
            }
        }
    }

    func testLineEndingsAreNotNormalized() throws {
        let decoded = try TextFile.decode(Data("a\r\nb\nc\r\n".utf8))
        XCTAssertEqual(decoded.text, "a\r\nb\nc\r\n")
        XCTAssertEqual(decoded.lineEnding, .crlf)
        XCTAssertTrue(decoded.hasMixedLineEndings)
    }

    func testFileWithoutBreaksDefaultsToLF() throws {
        let decoded = try TextFile.decode(Data("ahoj".utf8))
        XCTAssertEqual(decoded.lineEnding, .lf)
        XCTAssertFalse(decoded.hasMixedLineEndings)
    }

    func testBOMIsNotPartOfTheText() throws {
        let decoded = try TextFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data("é".utf8))
        XCTAssertEqual(decoded.text, "é")
        XCTAssertEqual(decoded.encoding, .utf8WithBOM)
        // "Reopen with UTF-8" on the same file keeps the BOM.
        let forced = try TextFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data("é".utf8), encoding: .utf8)
        XCTAssertEqual(forced.text, "é")
        XCTAssertEqual(forced.encoding, .utf8WithBOM)
    }

    func testUTF16IsWrittenWithBOM() throws {
        XCTAssertEqual(try TextFile.encode("a", encoding: .utf16LittleEndian), Data([0xFF, 0xFE, 0x61, 0x00]))
        XCTAssertEqual(try TextFile.encode("a", encoding: .utf16BigEndian), Data([0xFE, 0xFF, 0x00, 0x61]))
    }

    func testForcedUTF8OnInvalidBytesFails() throws {
        let windows1252 = try TextFile.encode("café", encoding: .windows1252)
        XCTAssertThrowsError(try TextFile.decode(windows1252, encoding: .utf8)) { error in
            XCTAssertEqual(error as? TextCodecError, .cannotDecode(.utf8))
        }
    }

    func testReopenUTF8FileAsWindows1252() throws {
        // A UTF-8 file read as Windows-1252 shows mojibake ("cafÃ©") but is still byte-exact.
        let bytes = Data("café".utf8)
        let decoded = try TextFile.decode(bytes, encoding: .windows1252)
        XCTAssertEqual(decoded.text, "cafÃ©")
        XCTAssertEqual(try TextFile.encode(decoded.text, encoding: .windows1252), bytes)
    }

    func testEncodeUnencodableThrowsWithCharacterAndLine() {
        XCTAssertThrowsError(try TextFile.encode("ok\nline 😀", encoding: .isoLatin1)) { error in
            guard case .cannotEncode(let encoding, let character)? = error as? TextCodecError else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(encoding, .isoLatin1)
            XCTAssertEqual(character?.character, "😀")
            XCTAssertEqual(character?.line, 2)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }
}
