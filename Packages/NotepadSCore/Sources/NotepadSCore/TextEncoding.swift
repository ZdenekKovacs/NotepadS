import Foundation

/// The text encodings NotepadS reads and writes.
///
/// UTF-16 is always written with a byte order mark (BOM). UTF-8 exists with and without BOM,
/// because both are common and a file must keep whichever it had.
public enum TextEncoding: String, CaseIterable, Hashable, Sendable {
    case utf8
    case utf8WithBOM
    case utf16LittleEndian
    case utf16BigEndian
    case windows1250
    case isoLatin2

    /// Label for menus, e.g. "Central European (Windows-1250)".
    public var displayName: String {
        switch self {
        case .utf8: return "Unicode (UTF-8)"
        case .utf8WithBOM: return "Unicode (UTF-8 with BOM)"
        case .utf16LittleEndian: return "Unicode (UTF-16 LE)"
        case .utf16BigEndian: return "Unicode (UTF-16 BE)"
        case .windows1250: return "Central European (Windows-1250)"
        case .isoLatin2: return "Central European (ISO 8859-2)"
        }
    }

    /// Short label for the status bar, e.g. "UTF-8".
    public var shortName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8WithBOM: return "UTF-8 with BOM"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .windows1250: return "Windows-1250"
        case .isoLatin2: return "ISO 8859-2"
        }
    }

    /// The bytes written at the start of the file, if any.
    public var byteOrderMark: [UInt8] {
        switch self {
        case .utf8WithBOM: return [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: return [0xFF, 0xFE]
        case .utf16BigEndian: return [0xFE, 0xFF]
        case .utf8, .windows1250, .isoLatin2: return []
        }
    }

    /// True for the Unicode encodings, which can represent any text.
    public var isUnicode: Bool {
        singleByteTable == nil
    }

    // MARK: - Encodability

    /// True if every character of `text` can be stored in this encoding without loss.
    public func canEncode(_ text: String) -> Bool {
        guard let table = singleByteTable else { return true }
        return text.unicodeScalars.allSatisfy { table.byteForScalar[$0.value] != nil }
    }

    /// The first character of `text` this encoding can't store, or nil if there is none.
    /// Used for error messages ("“😀” can't be saved in Windows-1250").
    public func firstUnencodableCharacter(in text: String) -> UnencodableCharacter? {
        guard let table = singleByteTable else { return nil }
        var utf16Offset = 0
        var line = 1
        for character in text {
            if character.unicodeScalars.contains(where: { table.byteForScalar[$0.value] == nil }) {
                return UnencodableCharacter(character: character, utf16Offset: utf16Offset, line: line)
            }
            // A Character can contain a whole "\r\n" break; count it as one line break.
            if character.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) {
                line += 1
            }
            utf16Offset += character.utf16.count
        }
        return nil
    }

    // MARK: - Encoding and decoding (without BOM handling; see TextFile)

    /// Decodes `bytes` (with any BOM already removed). Returns nil if they are not valid in this
    /// encoding. The single-byte encodings decode every byte sequence.
    func decode(_ bytes: Data) -> String? {
        if let table = singleByteTable {
            return table.decode(bytes)
        }
        let foundationEncoding: String.Encoding
        switch self {
        case .utf8, .utf8WithBOM: foundationEncoding = .utf8
        case .utf16LittleEndian: foundationEncoding = .utf16LittleEndian
        case .utf16BigEndian: foundationEncoding = .utf16BigEndian
        case .windows1250, .isoLatin2: return nil   // handled by the table above
        }
        // UTF-16 data must have an even number of bytes.
        if !isUTF8 && bytes.count % 2 != 0 { return nil }
        return String(data: bytes, encoding: foundationEncoding)
    }

    /// Encodes `text` (without BOM). Returns nil if some character can't be represented.
    func encode(_ text: String) -> Data? {
        if let table = singleByteTable {
            return table.encode(text)
        }
        switch self {
        case .utf8, .utf8WithBOM: return Data(text.utf8)
        case .utf16LittleEndian: return text.data(using: .utf16LittleEndian)
        case .utf16BigEndian: return text.data(using: .utf16BigEndian)
        case .windows1250, .isoLatin2: return nil
        }
    }

    private var isUTF8: Bool {
        self == .utf8 || self == .utf8WithBOM
    }

    private var singleByteTable: SingleByteTable? {
        switch self {
        case .windows1250: return SingleByteTable.windows1250
        case .isoLatin2: return SingleByteTable.isoLatin2
        default: return nil
        }
    }
}

/// A character that can't be stored in an encoding, with its position for error messages.
public struct UnencodableCharacter: Equatable, Sendable {
    public let character: Character
    /// Offset in UTF-16 code units from the start of the text (an `NSRange` location).
    public let utf16Offset: Int
    /// 1-based line number.
    public let line: Int
}

/// Byte ↔ Unicode table for an 8-bit encoding.
///
/// Why our own table instead of `String(data:encoding:)`: Foundation refuses the bytes that
/// Windows-1250 leaves undefined (0x81, 0x83, 0x88, 0x90, 0x98), so a file containing one of
/// them couldn't be opened at all, and Foundation's encoder may substitute look-alike
/// characters. Here every byte decodes to exactly one character and back, so opening and
/// saving is byte-exact for any file. The table is built once from Foundation's own mapping;
/// undefined bytes map to the C1 control character with the same number (U+0081 etc.),
/// as the WHATWG Encoding Standard does.
struct SingleByteTable: Sendable {
    let scalarForByte: [Unicode.Scalar]          // 256 entries
    let byteForScalar: [UInt32: UInt8]

    static let windows1250 = SingleByteTable(foundationEncoding: .windowsCP1250)
    static let isoLatin2 = SingleByteTable(foundationEncoding: .isoLatin2)

    init(foundationEncoding: String.Encoding) {
        var scalars: [Unicode.Scalar] = []
        var bytes: [UInt32: UInt8] = [:]
        for byte in 0...255 {
            let decoded = String(data: Data([UInt8(byte)]), encoding: foundationEncoding)
            let scalar: Unicode.Scalar
            if let decoded, decoded.unicodeScalars.count == 1, let only = decoded.unicodeScalars.first,
               bytes[only.value] == nil {
                scalar = only
            } else {
                // Undefined byte: keep it as the control character with the same code.
                // `Unicode.Scalar(UInt8)` is non-failable, so there is no unwrap here.
                scalar = Unicode.Scalar(UInt8(byte))
            }
            scalars.append(scalar)
            bytes[scalar.value] = UInt8(byte)
        }
        scalarForByte = scalars
        byteForScalar = bytes
    }

    func decode(_ data: Data) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(data.count)
        for byte in data {
            scalars.append(scalarForByte[Int(byte)])
        }
        return String(scalars)
    }

    func encode(_ text: String) -> Data? {
        var data = Data()
        data.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            guard let byte = byteForScalar[scalar.value] else { return nil }
            data.append(byte)
        }
        return data
    }
}
