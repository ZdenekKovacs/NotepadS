import Foundation

/// The characters of the ASCII panel (Notepad++'s "ASCII Codes Insertion Panel"): codes 0–255
/// in Windows-1252, the common Western code page. 0–127 is ASCII; 160–255 is the same as
/// ISO 8859-1 and Unicode. The five codes Windows-1252 leaves unused (0x81, 0x8D, 0x8F, 0x90,
/// 0x9D) are left out.
public enum CharacterTable {

    public struct Entry: Equatable, Sendable {
        /// The code in Windows-1252, 0–255.
        public let code: Int
        /// The character, e.g. "€" for code 128.
        public let character: String
        /// Name of a control or invisible character ("NUL", "TAB", "SP", "NBSP" …); nil otherwise.
        public let controlName: String?
        /// Named HTML entity, e.g. "&euro;"; nil if there is none.
        public let htmlName: String?

        /// "80" for code 128.
        public var hex: String { String(format: "%02X", code) }
        /// "U+20AC" for €.
        public var unicode: String { String(format: "U+%04X", scalar.value) }
        /// "&#8364;" for €: the Unicode code point, which is what HTML expects.
        public var htmlNumber: String { "&#\(scalar.value);" }

        private var scalar: Unicode.Scalar {
            // `character` is built from exactly one scalar below.
            character.unicodeScalars.first ?? Unicode.Scalar(0)
        }
    }

    public static let entries: [Entry] = (0...255).compactMap { code in
        let scalar = SingleByteTable.windows1252.scalarForByte[code]
        // Undefined in Windows-1252: the table keeps them as the C1 control with the same code.
        if (0x80...0x9F).contains(code), scalar.value == UInt32(code) { return nil }
        return Entry(code: code, character: String(Character(scalar)),
                     controlName: controlName(code: code, scalar: scalar), htmlName: htmlName(scalar))
    }

    private static func controlName(code: Int, scalar: Unicode.Scalar) -> String? {
        let names = ["NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", "TAB", "LF", "VT", "FF", "CR",
                     "SO", "SI", "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB", "CAN", "EM", "SUB", "ESC",
                     "FS", "GS", "RS", "US", "SP"]
        if code < names.count { return names[code] }
        switch scalar.value {
        case 0x7F: return "DEL"
        case 0xA0: return "NBSP"
        case 0xAD: return "SHY"
        default: return nil
        }
    }

    private static func htmlName(_ scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x22: return "&quot;"
        case 0x26: return "&amp;"
        case 0x27: return "&apos;"
        case 0x3C: return "&lt;"
        case 0x3E: return "&gt;"
        case 0xA0...0xFF: return "&\(latin1EntityNames[Int(scalar.value) - 0xA0]);"
        default: return windows1252EntityNames[scalar.value].map { "&\($0);" }
        }
    }

    /// HTML entity names of U+00A0 … U+00FF, in order.
    private static let latin1EntityNames = [
        "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo",
        "not", "shy", "reg", "macr", "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot",
        "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest",
        "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml",
        "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times",
        "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
        "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc", "euml",
        "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide",
        "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
    ]

    /// HTML entity names of the characters Windows-1252 has at 0x80–0x9F.
    private static let windows1252EntityNames: [UInt32: String] = [
        0x20AC: "euro", 0x201A: "sbquo", 0x0192: "fnof", 0x201E: "bdquo", 0x2026: "hellip", 0x2020: "dagger",
        0x2021: "Dagger", 0x02C6: "circ", 0x2030: "permil", 0x0160: "Scaron", 0x2039: "lsaquo", 0x0152: "OElig",
        0x017D: "Zcaron", 0x2018: "lsquo", 0x2019: "rsquo", 0x201C: "ldquo", 0x201D: "rdquo", 0x2022: "bull",
        0x2013: "ndash", 0x2014: "mdash", 0x02DC: "tilde", 0x2122: "trade", 0x0161: "scaron", 0x203A: "rsaquo",
        0x0153: "oelig", 0x017E: "zcaron", 0x0178: "Yuml",
    ]
}
