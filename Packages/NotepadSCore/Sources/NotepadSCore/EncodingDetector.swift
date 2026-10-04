import Foundation

/// Guesses the encoding of a file's bytes.
///
/// Order of checks:
/// 1. Byte order mark → UTF-8 with BOM, UTF-16 LE or UTF-16 BE.
/// 2. A NUL byte in the first 8 KB → binary (text files don't contain NUL; UTF-16 text does,
///    but it was recognized by its BOM in step 1).
/// 3. Valid UTF-8 → UTF-8 (pure ASCII is valid UTF-8 too).
/// 4. Otherwise Windows-1252, the legacy Western encoding most non-UTF-8 text files use.
///    ISO-8859-1 decodes 0xA0–0xFF identically and has only control characters in 0x80–0x9F,
///    which never appear in real text, so a Latin-1 file opened as Windows-1252 shows the same
///    text and still saves byte for byte. "Reopen with Encoding" switches if needed.
public enum EncodingDetector {

    /// How many leading bytes are checked for NUL.
    static let binarySampleSize = 8 * 1024

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
        return .windows1252
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
