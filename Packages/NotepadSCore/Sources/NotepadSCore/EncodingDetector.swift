import Foundation

/// Guesses the encoding of a file's bytes.
///
/// Order of checks:
/// 1. Byte order mark → UTF-8 with BOM, UTF-16 LE or UTF-16 BE.
/// 2. A NUL byte in the first 8 KB → binary (text files don't contain NUL; UTF-16 text does,
///    but it was recognized by its BOM in step 1).
/// 3. Valid UTF-8 → UTF-8 (pure ASCII is valid UTF-8 too).
/// 4. Otherwise one of the Central European 8-bit encodings. Windows-1250 and ISO-8859-2 both
///    decode any byte sequence and differ only in 0x80–0xBF, so this is a heuristic tuned for
///    Czech: any byte 0x80–0x9F → Windows-1250 (ISO-8859-2 has only control characters
///    there); else a byte that is a Czech letter only in ISO-8859-2 (Š Ť Ž š ť ž) →
///    ISO-8859-2; else Windows-1250. "Reopen with Encoding" fixes a wrong guess.
public enum EncodingDetector {

    /// How many leading bytes are checked for NUL.
    static let binarySampleSize = 8 * 1024

    /// Bytes where ISO-8859-2 has Š Ť Ž š ť ž; in Windows-1250 these are other characters
    /// (©, «, ®, ą, », ľ), which are rare in Czech text.
    private static let isoLatin2CzechLetters: Set<UInt8> = [0xA9, 0xAB, 0xAE, 0xB9, 0xBB, 0xBE]

    /// Returns the detected encoding, or throws `TextCodecError.binaryFile`.
    public static func detect(_ data: Data) throws -> TextEncoding {
        if let encoding = encodingFromByteOrderMark(data) {
            return encoding
        }
        if data.prefix(binarySampleSize).contains(0) {
            throw TextCodecError.binaryFile
        }
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        if data.contains(where: { (0x80...0x9F).contains($0) }) {
            return .windows1250
        }
        if data.contains(where: { isoLatin2CzechLetters.contains($0) }) {
            return .isoLatin2
        }
        return .windows1250
    }

    /// The encoding announced by a byte order mark at the start of `data`, if any.
    public static func encodingFromByteOrderMark(_ data: Data) -> TextEncoding? {
        for encoding in [TextEncoding.utf8WithBOM, .utf16LittleEndian, .utf16BigEndian]
        where data.starts(with: encoding.byteOrderMark) {
            return encoding
        }
        return nil
    }
}
