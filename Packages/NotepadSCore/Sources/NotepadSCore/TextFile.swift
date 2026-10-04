import Foundation

/// Converts between a file's bytes and the editor's text.
///
/// The text is kept exactly as in the file: line breaks are not normalized, so
/// `encode(decode(bytes).text, encoding: decode(bytes).encoding)` returns the original bytes.
public enum TextFile {

    /// The result of reading a file.
    public struct Decoded: Equatable, Sendable {
        /// The text, with line breaks exactly as in the file.
        public let text: String
        public let encoding: TextEncoding
        /// The most frequent line-break style; LF if the file has no line breaks.
        /// The editor uses it for line breaks it inserts.
        public let lineEnding: LineEnding
        /// True if the file contains more than one line-break style.
        public let hasMixedLineEndings: Bool
    }

    /// Decodes a file.
    ///
    /// - Parameters:
    ///   - data: the file's bytes.
    ///   - encoding: the encoding to use ("Reopen with Encoding"), or nil to detect it.
    /// - Throws: `TextCodecError.binaryFile` if detection finds binary data,
    ///   `TextCodecError.cannotDecode` if the bytes are not valid in the forced encoding.
    public static func decode(_ data: Data, encoding forcedEncoding: TextEncoding? = nil) throws -> Decoded {
        let encoding = try forcedEncoding ?? EncodingDetector.detect(data)

        // Remove the BOM if the file has the one this encoding uses. A forced UTF-8 on a file
        // with a UTF-8 BOM behaves like "UTF-8 with BOM", so the BOM isn't shown as text.
        var body = data
        var effectiveEncoding = encoding
        if encoding == .utf8, data.starts(with: TextEncoding.utf8WithBOM.byteOrderMark) {
            effectiveEncoding = .utf8WithBOM
        }
        let byteOrderMark = effectiveEncoding.byteOrderMark
        if !byteOrderMark.isEmpty, data.starts(with: byteOrderMark) {
            body = data.dropFirst(byteOrderMark.count)
        }

        guard let text = effectiveEncoding.decode(Data(body)) else {
            throw TextCodecError.cannotDecode(encoding)
        }
        let counts = LineEnding.count(in: text)
        return Decoded(text: text,
                       encoding: effectiveEncoding,
                       lineEnding: counts.dominant ?? .lf,
                       hasMixedLineEndings: counts.isMixed)
    }

    /// Encodes `text` unchanged (line breaks included), with the encoding's BOM.
    /// - Throws: `TextCodecError.cannotEncode` naming the first character that can't be stored.
    public static func encode(_ text: String, encoding: TextEncoding) throws -> Data {
        guard let body = encoding.encode(text) else {
            throw TextCodecError.cannotEncode(encoding, encoding.firstUnencodableCharacter(in: text))
        }
        return Data(encoding.byteOrderMark) + body
    }
}
