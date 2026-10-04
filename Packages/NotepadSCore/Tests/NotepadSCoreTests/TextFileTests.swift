import XCTest
@testable import NotepadSCore

final class TextEncodingTests: XCTestCase {

    private let czech = "Příliš žluťoučký kůň úpěl ďábelské ódy. PŘÍLIŠ ŽLUŤOUČKÝ KŮŇ ÚPĚL ĎÁBELSKÉ ÓDY."

    func testSingleByteTablesAreOneToOne() {
        for table in [SingleByteTable.windows1250, .isoLatin2] {
            XCTAssertEqual(table.scalarForByte.count, 256)
            XCTAssertEqual(Set(table.scalarForByte.map(\.value)).count, 256)
            XCTAssertEqual(table.byteForScalar.count, 256)
        }
    }

    func testKnownCzechBytes() throws {
        // Windows-1250: š=0x9A ž=0x9E ť=0x9D ř=0xF8 ů=0xF9. ISO-8859-2: š=0xB9 ž=0xBE ť=0xBB.
        XCTAssertEqual(try TextFile.encode("šžťřů", encoding: .windows1250), Data([0x9A, 0x9E, 0x9D, 0xF8, 0xF9]))
        XCTAssertEqual(try TextFile.encode("šžťřů", encoding: .isoLatin2), Data([0xB9, 0xBE, 0xBB, 0xF8, 0xF9]))
    }

    func testEveryByteRoundTripsInSingleByteEncodings() throws {
        let allBytes = Data((0...255).map { UInt8($0) })
        for encoding in [TextEncoding.windows1250, .isoLatin2] {
            let text = try XCTUnwrap(encoding.decode(allBytes))
            XCTAssertEqual(encoding.encode(text), allBytes, "\(encoding)")
        }
    }

    func testCanEncode() {
        XCTAssertTrue(TextEncoding.windows1250.canEncode(czech))
        XCTAssertTrue(TextEncoding.isoLatin2.canEncode(czech))
        XCTAssertFalse(TextEncoding.windows1250.canEncode("ahoj 😀"))
        XCTAssertFalse(TextEncoding.isoLatin2.canEncode("€"))           // € exists only in Windows-1250
        XCTAssertTrue(TextEncoding.windows1250.canEncode("€"))
        XCTAssertTrue(TextEncoding.utf8.canEncode("😀"))
        // Decomposed "é" (e + combining accent) is not a single Windows-1250 byte.
        XCTAssertFalse(TextEncoding.windows1250.canEncode("e\u{301}"))
    }

    func testFirstUnencodableCharacter() throws {
        let found = try XCTUnwrap(TextEncoding.windows1250.firstUnencodableCharacter(in: "ř\r\nž\r😀x"))
        XCTAssertEqual(found.character, "😀")
        XCTAssertEqual(found.line, 3)
        XCTAssertEqual(found.utf16Offset, 5)
        XCTAssertNil(TextEncoding.windows1250.firstUnencodableCharacter(in: czech))
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
        XCTAssertEqual(try EncodingDetector.detect(Data("žluťoučký 😀".utf8)), .utf8)
        XCTAssertEqual(try EncodingDetector.detect(Data()), .utf8)
    }

    func testWindows1250() throws {
        let data = try TextFile.encode("Příliš žluťoučký kůň", encoding: .windows1250)
        XCTAssertEqual(try EncodingDetector.detect(data), .windows1250)
    }

    func testISOLatin2() throws {
        let data = try TextFile.encode("Příliš žluťoučký kůň", encoding: .isoLatin2)
        XCTAssertEqual(try EncodingDetector.detect(data), .isoLatin2)
    }

    func testAmbiguousEightBitTextDefaultsToWindows1250() throws {
        // "čeká" is identical in both encodings and not valid UTF-8.
        let data = try TextFile.encode("čeká", encoding: .isoLatin2)
        XCTAssertEqual(try EncodingDetector.detect(data), .windows1250)
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
        "Příliš\r\nžluťoučký\r\nkůň",
        "úpěl\rďábelské\ródy\r",
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
                // Without a BOM an ISO-8859-2 file may be detected as Windows-1250; force it.
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
        let decoded = try TextFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data("ř".utf8))
        XCTAssertEqual(decoded.text, "ř")
        XCTAssertEqual(decoded.encoding, .utf8WithBOM)
        // "Reopen with UTF-8" on the same file keeps the BOM.
        let forced = try TextFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data("ř".utf8), encoding: .utf8)
        XCTAssertEqual(forced.text, "ř")
        XCTAssertEqual(forced.encoding, .utf8WithBOM)
    }

    func testUTF16IsWrittenWithBOM() throws {
        XCTAssertEqual(try TextFile.encode("a", encoding: .utf16LittleEndian), Data([0xFF, 0xFE, 0x61, 0x00]))
        XCTAssertEqual(try TextFile.encode("a", encoding: .utf16BigEndian), Data([0xFE, 0xFF, 0x00, 0x61]))
    }

    func testForcedUTF8OnInvalidBytesFails() throws {
        let windows1250 = try TextFile.encode("žluť", encoding: .windows1250)
        XCTAssertThrowsError(try TextFile.decode(windows1250, encoding: .utf8)) { error in
            XCTAssertEqual(error as? TextCodecError, .cannotDecode(.utf8))
        }
    }

    func testReopenUTF8FileAsWindows1250() throws {
        // A UTF-8 file read as Windows-1250 shows mojibake but is still byte-exact.
        let bytes = Data("žluť".utf8)
        let decoded = try TextFile.decode(bytes, encoding: .windows1250)
        XCTAssertNotEqual(decoded.text, "žluť")
        XCTAssertEqual(try TextFile.encode(decoded.text, encoding: .windows1250), bytes)
    }

    func testEncodeUnencodableThrowsWithCharacterAndLine() {
        XCTAssertThrowsError(try TextFile.encode("ok\nřádek 😀", encoding: .isoLatin2)) { error in
            guard case .cannotEncode(let encoding, let character)? = error as? TextCodecError else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(encoding, .isoLatin2)
            XCTAssertEqual(character?.character, "😀")
            XCTAssertEqual(character?.line, 2)
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
    }
}
