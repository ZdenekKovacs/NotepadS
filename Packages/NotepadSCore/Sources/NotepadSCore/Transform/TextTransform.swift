import Foundation

/// What a transformation needs to know besides the text.
public struct TransformContext: Sendable {
    /// Style for line breaks a transformation creates (the document's style).
    public var lineEnding: LineEnding
    /// For sorting and case conversion.
    public var locale: Locale
    /// One level of indentation, for formatters (e.g. four spaces).
    public var indentation: String

    public init(lineEnding: LineEnding, locale: Locale = .current, indentation: String = "    ") {
        self.lineEnding = lineEnding
        self.locale = locale
        self.indentation = indentation
    }
}

/// Why a transformation couldn't run. The text is then left unchanged.
public struct TransformError: Error, Equatable, LocalizedError {
    /// What is wrong, e.g. "Expected “,” or “}”".
    public let message: String
    /// 1-based position in the transformed text, if the problem has one.
    public let line: Int?
    public let column: Int?

    public init(_ message: String, line: Int? = nil, column: Int? = nil) {
        self.message = message
        self.line = line
        self.column = column
    }

    public var errorDescription: String? {
        if let line, let column {
            return String(localized: "Line \(line), column \(column): \(message)", bundle: .module,
                          comment: "Transformation error with its position")
        }
        return message
    }
}

/// A text transformation from the Text menu: a pure function from text to text.
///
/// The editor applies it to the selection, or to the whole document when nothing is selected,
/// as one undo step. Line-based transformations work on whole lines.
public enum TextTransform: String, CaseIterable, Sendable {
    case formatJSON
    case minifyJSON
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case uppercase
    case lowercase
    case titleCase
    case camelCase
    case snakeCase
    case kebabCase
    case sortLinesAscending
    case sortLinesDescending
    case removeDuplicateLines
    case trimTrailingWhitespace
    case joinLines
    case reverseLines
    case shuffleLines
    case removeConsecutiveDuplicateLines
    case removeEmptyLines

    /// Menu title.
    public var name: String {
        switch self {
        case .formatJSON:
            return String(localized: "Format JSON", bundle: .module, comment: "Text menu item: pretty-print JSON")
        case .minifyJSON:
            return String(localized: "Minify JSON", bundle: .module, comment: "Text menu item: remove whitespace from JSON")
        case .base64Encode:
            return String(localized: "Base64 Encode", bundle: .module, comment: "Text menu item")
        case .base64Decode:
            return String(localized: "Base64 Decode", bundle: .module, comment: "Text menu item")
        case .urlEncode:
            return String(localized: "URL Encode", bundle: .module, comment: "Text menu item: percent-encoding")
        case .urlDecode:
            return String(localized: "URL Decode", bundle: .module, comment: "Text menu item: percent-encoding")
        case .uppercase:
            return String(localized: "UPPERCASE", bundle: .module, comment: "Text menu item: convert to upper case")
        case .lowercase:
            return String(localized: "lowercase", bundle: .module, comment: "Text menu item: convert to lower case")
        case .titleCase:
            return String(localized: "Title Case", bundle: .module, comment: "Text menu item: capitalize words")
        case .camelCase:
            return "camelCase"   // the style's own name; not translated
        case .snakeCase:
            return "snake_case"
        case .kebabCase:
            return "kebab-case"
        case .sortLinesAscending:
            return String(localized: "Sort Lines Ascending", bundle: .module, comment: "Text menu item")
        case .sortLinesDescending:
            return String(localized: "Sort Lines Descending", bundle: .module, comment: "Text menu item")
        case .removeDuplicateLines:
            return String(localized: "Remove Duplicate Lines", bundle: .module, comment: "Text menu item")
        case .trimTrailingWhitespace:
            return String(localized: "Trim Trailing Whitespace", bundle: .module, comment: "Text menu item")
        case .joinLines:
            return String(localized: "Join Lines", bundle: .module, comment: "Text › Lines menu item")
        case .reverseLines:
            return String(localized: "Reverse Line Order", bundle: .module, comment: "Text › Lines menu item")
        case .shuffleLines:
            return String(localized: "Shuffle Lines", bundle: .module, comment: "Text › Lines menu item: random order")
        case .removeConsecutiveDuplicateLines:
            return String(localized: "Remove Consecutive Duplicate Lines", bundle: .module,
                          comment: "Text › Lines menu item: remove a line equal to the line before it")
        case .removeEmptyLines:
            return String(localized: "Remove Empty Lines", bundle: .module,
                          comment: "Text › Lines menu item: also lines with only spaces and tabs")
        }
    }

    /// True if the transformation works on whole lines: the editor then extends a partial
    /// selection to the lines it touches.
    public var isLineBased: Bool {
        switch self {
        case .sortLinesAscending, .sortLinesDescending, .removeDuplicateLines, .trimTrailingWhitespace,
             .joinLines, .reverseLines, .shuffleLines, .removeConsecutiveDuplicateLines, .removeEmptyLines:
            return true
        case .formatJSON, .minifyJSON, .base64Encode, .base64Decode, .urlEncode, .urlDecode,
             .uppercase, .lowercase, .titleCase, .camelCase, .snakeCase, .kebabCase:
            return false
        }
    }

    /// Transforms `text`. Throws `TransformError` if the text isn't valid input.
    public func apply(to text: String, context: TransformContext) throws -> String {
        switch self {
        case .formatJSON:
            return try JSONFormatter.format(text, indent: context.indentation, lineEnding: context.lineEnding)
        case .minifyJSON:
            return try JSONFormatter.minify(text, lineEnding: context.lineEnding)
        case .base64Encode:
            return Codecs.base64Encode(text)
        case .base64Decode:
            return try Codecs.base64Decode(text, context: context)
        case .urlEncode:
            return Codecs.urlEncode(text)
        case .urlDecode:
            return try Codecs.urlDecode(text, context: context)
        case .uppercase:
            return text.uppercased(with: context.locale)
        case .lowercase:
            return text.lowercased(with: context.locale)
        case .titleCase:
            return text.capitalized(with: context.locale)
        case .camelCase:
            return CaseConversion.identifiers(text, style: .camel, locale: context.locale)
        case .snakeCase:
            return CaseConversion.identifiers(text, style: .snake, locale: context.locale)
        case .kebabCase:
            return CaseConversion.identifiers(text, style: .kebab, locale: context.locale)
        case .sortLinesAscending:
            return LineTools.sort(text, ascending: true, context: context)
        case .sortLinesDescending:
            return LineTools.sort(text, ascending: false, context: context)
        case .removeDuplicateLines:
            return LineTools.removeDuplicates(text, context: context)
        case .trimTrailingWhitespace:
            return LineTools.trimTrailingWhitespace(text)
        case .joinLines:
            return LineTools.join(text)
        case .reverseLines:
            return LineTools.reverse(text, context: context)
        case .shuffleLines:
            var generator = SystemRandomNumberGenerator()
            return LineTools.shuffle(text, context: context, using: &generator)
        case .removeConsecutiveDuplicateLines:
            return LineTools.removeConsecutiveDuplicates(text, context: context)
        case .removeEmptyLines:
            return LineTools.removeEmptyLines(text, context: context)
        }
    }
}
