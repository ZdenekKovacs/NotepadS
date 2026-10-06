import Foundation

/// What a transformation needs to know besides the text.
public struct TransformContext: Sendable {
    /// Style for line breaks a transformation creates (the document's style).
    public var lineEnding: LineEnding
    /// For sorting and case conversion.
    public var locale: Locale

    public init(lineEnding: LineEnding, locale: Locale = .current) {
        self.lineEnding = lineEnding
        self.locale = locale
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
    case sortLinesAscending
    case sortLinesDescending
    case removeDuplicateLines
    case trimTrailingWhitespace

    /// Menu title.
    public var name: String {
        switch self {
        case .sortLinesAscending:
            return String(localized: "Sort Lines Ascending", bundle: .module, comment: "Text menu item")
        case .sortLinesDescending:
            return String(localized: "Sort Lines Descending", bundle: .module, comment: "Text menu item")
        case .removeDuplicateLines:
            return String(localized: "Remove Duplicate Lines", bundle: .module, comment: "Text menu item")
        case .trimTrailingWhitespace:
            return String(localized: "Trim Trailing Whitespace", bundle: .module, comment: "Text menu item")
        }
    }

    /// True if the transformation works on whole lines: the editor then extends a partial
    /// selection to the lines it touches.
    public var isLineBased: Bool {
        switch self {
        case .sortLinesAscending, .sortLinesDescending, .removeDuplicateLines, .trimTrailingWhitespace:
            return true
        }
    }

    /// Transforms `text`. Throws `TransformError` if the text isn't valid input.
    public func apply(to text: String, context: TransformContext) throws -> String {
        switch self {
        case .sortLinesAscending:
            return LineTools.sort(text, ascending: true, context: context)
        case .sortLinesDescending:
            return LineTools.sort(text, ascending: false, context: context)
        case .removeDuplicateLines:
            return LineTools.removeDuplicates(text, context: context)
        case .trimTrailingWhitespace:
            return LineTools.trimTrailingWhitespace(text)
        }
    }
}
