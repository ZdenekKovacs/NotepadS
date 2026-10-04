import Foundation

/// A line-break style.
///
/// The editor keeps line breaks exactly as they are in the file (possibly mixed). A document's
/// `LineEnding` is only the style used for line breaks the editor *inserts* (Enter, paste,
/// transformations) and the target of the explicit "Convert Line Endings" command.
public enum LineEnding: String, CaseIterable, Hashable, Sendable {
    case lf
    case crlf
    case cr

    /// The characters of this line break.
    public var string: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    /// Length in UTF-16 code units (the unit `NSString` and `NSRange` use).
    public var utf16Length: Int {
        self == .crlf ? 2 : 1
    }

    /// Short label for the status bar, e.g. "CRLF".
    public var shortName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }

    /// Label for menus, e.g. "CRLF (Windows)".
    public var displayName: String {
        switch self {
        case .lf: return "LF (macOS, Linux)"
        case .crlf: return "CRLF (Windows)"
        case .cr: return "CR (classic Mac OS)"
        }
    }

    // MARK: - Detection and conversion

    /// Counts the line breaks of each style in `text`.
    ///
    /// Works on UTF-8 bytes: in Swift `"\r\n"` is a single `Character`, so a `Character`-based
    /// scan would miss the `\r` in it. `\r` and `\n` never occur inside a multi-byte UTF-8
    /// sequence, so a byte scan is exact.
    public static func count(in text: String) -> LineEndingCounts {
        var counts = LineEndingCounts()
        var previousWasCR = false
        for byte in text.utf8 {
            if byte == Byte.lineFeed {
                if previousWasCR {
                    counts.add(.crlf)
                } else {
                    counts.add(.lf)
                }
                previousWasCR = false
            } else {
                if previousWasCR {
                    counts.add(.cr)
                }
                previousWasCR = byte == Byte.carriageReturn
            }
        }
        if previousWasCR {
            counts.add(.cr)
        }
        return counts
    }

    /// Replaces every line break (`\r\n`, `\r`, `\n`) with `\n`.
    public static func normalizeToLF(_ text: String) -> String {
        // Fast path: no `\r` means the text is already LF-only.
        guard text.utf8.contains(Byte.carriageReturn) else { return text }
        // Order matters: replace the two-character break first, so "\r\n" becomes one "\n".
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Converts LF-only text to `lineEnding`.
    public static func convert(fromLF text: String, to lineEnding: LineEnding) -> String {
        guard lineEnding != .lf else { return text }
        return text.replacingOccurrences(of: "\n", with: lineEnding.string)
    }

    /// Converts every line break in `text`, whatever its style, to `lineEnding`.
    /// Used for pasted/dropped text and for the "Convert Line Endings" command.
    public static func convertAll(_ text: String, to lineEnding: LineEnding) -> String {
        convert(fromLF: normalizeToLF(text), to: lineEnding)
    }
}

/// How many line breaks of each style a text contains.
public struct LineEndingCounts: Equatable, Sendable {
    public var lf = 0
    public var crlf = 0
    public var cr = 0

    public init(lf: Int = 0, crlf: Int = 0, cr: Int = 0) {
        self.lf = lf
        self.crlf = crlf
        self.cr = cr
    }

    public var total: Int { lf + crlf + cr }

    /// The most frequent style, or nil if there are no line breaks.
    /// Ties are resolved in the order LF, CRLF, CR.
    public var dominant: LineEnding? {
        guard total > 0 else { return nil }
        var best = LineEnding.lf
        for style in [LineEnding.crlf, .cr] where self[style] > self[best] {
            best = style
        }
        return best
    }

    /// True if more than one style occurs.
    public var isMixed: Bool {
        [lf, crlf, cr].filter { $0 > 0 }.count > 1
    }

    public subscript(style: LineEnding) -> Int {
        get {
            switch style {
            case .lf: return lf
            case .crlf: return crlf
            case .cr: return cr
            }
        }
        set {
            switch style {
            case .lf: lf = newValue
            case .crlf: crlf = newValue
            case .cr: cr = newValue
            }
        }
    }

    mutating func add(_ style: LineEnding, count: Int = 1) {
        self[style] += count
    }
}

/// Byte and UTF-16 values used by the line-break scanners.
enum Byte {
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
}

enum UTF16Unit {
    static let lineFeed: unichar = 0x0A
    static let carriageReturn: unichar = 0x0D
}
