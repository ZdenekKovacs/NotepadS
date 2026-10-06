import Foundation

/// How to interpret the search text.
public struct SearchOptions: Equatable, Sendable {
    /// Treat the search text as a regular expression (ICU syntax, as `NSRegularExpression`),
    /// and the replacement as a template with `$1`, `$2` … and `\n`, `\t`.
    public var isRegularExpression: Bool
    public var ignoresCase: Bool

    public init(isRegularExpression: Bool = false, ignoresCase: Bool = false) {
        self.isRegularExpression = isRegularExpression
        self.ignoresCase = ignoresCase
    }
}

/// A search that can't run: an empty or invalid pattern.
public struct SearchError: Error, Equatable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Finds and replaces text with plain text or a regular expression.
///
/// In regular-expression mode `^` and `$` match at the start and end of every line (with any
/// line-break style), and `.` doesn't match line breaks.
public struct TextSearch {
    private let regex: NSRegularExpression
    public let options: SearchOptions

    public init(pattern: String, options: SearchOptions) throws {
        guard !pattern.isEmpty else {
            throw SearchError(message: String(localized: "Enter text to find.", bundle: .module, comment: "Search error"))
        }
        var regexOptions: NSRegularExpression.Options = [.anchorsMatchLines]
        if options.ignoresCase { regexOptions.insert(.caseInsensitive) }
        let source = options.isRegularExpression ? pattern : NSRegularExpression.escapedPattern(for: pattern)
        do {
            regex = try NSRegularExpression(pattern: source, options: regexOptions)
        } catch {
            throw SearchError(message: String(localized: "The regular expression isn’t valid.", bundle: .module,
                                              comment: "Search error"))
        }
        self.options = options
    }

    /// All matches in `range` (the whole text by default), in order.
    public func matches(in text: NSString, range: NSRange? = nil) -> [NSRange] {
        let searchRange = range ?? NSRange(location: 0, length: text.length)
        return regex.matches(in: text as String, options: [], range: searchRange).map(\.range)
    }

    /// The first match starting at or after `location`; with `wraps`, otherwise the first
    /// match in the text. An empty match exactly at `location` is skipped, so repeated
    /// "Find Next" moves on.
    public func nextMatch(in text: NSString, from location: Int, wraps: Bool) -> NSRange? {
        let all = matches(in: text)
        if let match = all.first(where: { $0.location > location || ($0.location == location && $0.length > 0) }) {
            return match
        }
        return wraps ? all.first : nil
    }

    /// The last match starting before `location`; with `wraps`, otherwise the last match.
    public func previousMatch(in text: NSString, before location: Int, wraps: Bool) -> NSRange? {
        let all = matches(in: text)
        if let match = all.last(where: { $0.location < location }) {
            return match
        }
        return wraps ? all.last : nil
    }

    /// The replacement text for one match. `template` may refer to groups (`$1`) in
    /// regular-expression mode; `\n` there becomes a line break in the document's style.
    public func replacement(for match: NSRange, in text: NSString, template: String, lineEnding: LineEnding) -> String {
        guard let result = regex.firstMatch(in: text as String, options: [.anchored, .withTransparentBounds],
                                            range: NSRange(location: match.location, length: text.length - match.location))
        else { return "" }
        return regex.replacementString(for: result, in: text as String, offset: 0,
                                       template: preparedTemplate(template, lineEnding: lineEnding))
    }

    /// Replaces every match in `range` and returns the new text for `range` and the number of
    /// replacements.
    public func replaceAll(in text: NSString, range: NSRange, template: String,
                           lineEnding: LineEnding) -> (text: String, count: Int) {
        let original = NSMutableString(string: text.substring(with: range))
        let count = regex.replaceMatches(in: original, options: [], range: NSRange(location: 0, length: original.length),
                                         withTemplate: preparedTemplate(template, lineEnding: lineEnding))
        return (original as String, count)
    }

    /// Plain-text mode: the replacement is used as typed. Regular-expression mode: `$1` and
    /// `\$` work as in `NSRegularExpression`, and `\n`, `\r`, `\t` become a line break (in the
    /// document's style, as every break the editor inserts) and a tab.
    func preparedTemplate(_ template: String, lineEnding: LineEnding) -> String {
        guard options.isRegularExpression else {
            return NSRegularExpression.escapedTemplate(for: template)
        }
        var result = ""
        var iterator = template.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "n", "r": result += lineEnding.string
            case "t": result += "\t"
            default:
                result.append(character)   // keep "\\" and "\$" for NSRegularExpression
                result.append(next)
            }
        }
        return result
    }
}
