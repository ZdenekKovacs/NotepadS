import XCTest
@testable import NotepadSCore

/// The Notepad++ case conversions: Title Case keeping other letters, Sentence case (both
/// variants), iNVERT cASE and rAnDoM cAsE.
final class MoreCaseConversionTests: XCTestCase {

    private func apply(_ transform: TextTransform, _ text: String) throws -> String {
        try transform.apply(to: text, context: TransformContext(lineEnding: .lf, locale: Locale(identifier: "en_US")))
    }

    func testTitleCaseKeepingOtherLetters() throws {
        XCTAssertEqual(try apply(.titleCaseKeepingOtherLetters, "an HTTP server for iPhone apps"), "An HTTP Server For IPhone Apps")
        XCTAssertEqual(try apply(.titleCaseKeepingOtherLetters, "don’t stop, it's crème-brûlée"), "Don’t Stop, It's Crème-Brûlée",
                       "an apostrophe doesn't start a word")
        XCTAssertEqual(try apply(.titleCaseKeepingOtherLetters, "a\r\nb\rc😀d 2nd"), "A\r\nB\rC😀D 2nd",
                       "line breaks and emoji separate words; a digit starts a word that stays as it is")
    }

    func testSentenceCase() throws {
        XCTAssertEqual(try apply(.sentenceCase, "hello WORLD. this IS it! and? yes"), "Hello world. This is it! And? Yes")
        XCTAssertEqual(try apply(.sentenceCase, "  ÉTÉ.\r\nčau\n"), "  Été.\r\nČau\n", "a sentence can start on the next line")
        XCTAssertEqual(try apply(.sentenceCase, "version 2.0 is out"), "Version 2.0 is out", "no space after the dot: no new sentence")
    }

    func testSentenceCaseKeepingOtherLetters() throws {
        XCTAssertEqual(try apply(.sentenceCaseKeepingOtherLetters, "the HTTP server. it runs on iOS."),
                       "The HTTP server. It runs on iOS.")
    }

    func testInvertCase() throws {
        XCTAssertEqual(try apply(.invertCase, "Hello wORLD Ñandú 123 😀\r\n"), "hELLO World ñANDÚ 123 😀\r\n")
    }

    func testRandomCaseChangesOnlyTheCaseOfLetters() throws {
        let text = "Příliš žluťoučký kůň 123 😀\r\nabc"
        let result = try apply(.randomCase, text)
        XCTAssertEqual(result.lowercased(), text.lowercased())
        XCTAssertTrue(result.utf8.contains(0x0D), "the CRLF stays")
        var generator = SplitMix(seed: 7)
        let seeded = CaseConversion.randomCase(String(repeating: "a", count: 40), locale: Locale(identifier: "en_US"), using: &generator)
        XCTAssertTrue(seeded.contains("a") && seeded.contains("A"), "with this seed both cases appear")
    }

    func testAllAreNotLineBased() {
        for transform in [TextTransform.titleCaseKeepingOtherLetters, .sentenceCase, .sentenceCaseKeepingOtherLetters,
                          .invertCase, .randomCase] {
            XCTAssertFalse(transform.isLineBased, transform.rawValue)
        }
    }
}

/// A seeded random number generator, so the test always gives the same letters.
private struct SplitMix: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
