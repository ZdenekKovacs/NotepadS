import Foundation

/// Re-indents or minifies JSON by changing whitespace only.
///
/// Why not `JSONSerialization` or `Codable`: they parse into objects and write them back, which
/// loses the key order and rewrites numbers (`1.0` becomes `1`, big integers lose precision).
/// This formatter reads the text token by token and copies every string, number and literal
/// exactly as written. Invalid JSON is reported with its line and column, and nothing changes.
enum JSONFormatter {

    /// Pretty-prints with one value per line, nested values indented by `indent`.
    static func format(_ text: String, indent: String, lineEnding: LineEnding) throws -> String {
        var writer = Writer(text: text, pretty: true, indent: indent, newline: lineEnding.string)
        return try writer.run()
    }

    /// Removes all whitespace outside strings.
    static func minify(_ text: String, lineEnding: LineEnding) throws -> String {
        var writer = Writer(text: text, pretty: false, indent: "", newline: lineEnding.string)
        return try writer.run()
    }

    /// Deeper nesting is refused instead of risking a stack overflow in the recursive reader.
    static let maximumDepth = 512

    private struct Writer {
        let scalars: [Unicode.Scalar]
        let pretty: Bool
        let indentScalars: [Unicode.Scalar]
        let newlineScalars: [Unicode.Scalar]
        var position = 0
        var output = String.UnicodeScalarView()
        // Position of `position` for error messages, 1-based.
        var line = 1
        var column = 1

        init(text: String, pretty: Bool, indent: String, newline: String) {
            scalars = Array(text.unicodeScalars)
            self.pretty = pretty
            indentScalars = Array(indent.unicodeScalars)
            newlineScalars = Array(newline.unicodeScalars)
            output.reserveCapacity(scalars.count)
        }

        mutating func run() throws -> String {
            skipWhitespace()
            guard position < scalars.count else {
                throw error(String(localized: "Expected a JSON value.", bundle: .module, comment: "JSON error"))
            }
            try writeValue(depth: 0)
            let endsWithLineBreak = scalars.last == "\n" || scalars.last == "\r"
            skipWhitespace()
            guard position == scalars.count else {
                throw error(String(localized: "Unexpected text after the end of the JSON value.", bundle: .module,
                                   comment: "JSON error"))
            }
            // Keep a final line break if the input had one.
            if endsWithLineBreak {
                appendNewline()
            }
            return String(output)
        }

        // MARK: Values

        private mutating func writeValue(depth: Int) throws {
            guard depth < JSONFormatter.maximumDepth else {
                throw error(String(localized: "The JSON is nested too deeply.", bundle: .module, comment: "JSON error"))
            }
            guard let scalar = current else {
                throw error(String(localized: "Expected a JSON value.", bundle: .module, comment: "JSON error"))
            }
            switch scalar {
            case "{": try writeContainer(open: "{", close: "}", depth: depth, isObject: true)
            case "[": try writeContainer(open: "[", close: "]", depth: depth, isObject: false)
            case "\"": try copyString()
            case "-", "0"..."9": try copyNumber()
            case "t": try copyLiteral("true")
            case "f": try copyLiteral("false")
            case "n": try copyLiteral("null")
            default: throw unexpected(scalar)
            }
        }

        private mutating func writeContainer(open: Unicode.Scalar, close: Unicode.Scalar, depth: Int,
                                             isObject: Bool) throws {
            advance()
            output.append(open)
            skipWhitespace()
            if current == close {
                advance()
                output.append(close)   // empty: {} or []
                return
            }
            while true {
                writeLineBreak(depth: depth + 1)
                if isObject {
                    guard current == "\"" else {
                        throw expected(String(localized: "a key in double quotes", bundle: .module,
                                              comment: "JSON error: what was expected"))
                    }
                    try copyString()
                    skipWhitespace()
                    guard current == ":" else { throw expected("“:”") }
                    advance()
                    output.append(":")
                    if pretty { output.append(" ") }
                    skipWhitespace()
                }
                try writeValue(depth: depth + 1)
                skipWhitespace()
                if current == "," {
                    advance()
                    output.append(",")
                    skipWhitespace()
                } else if current == close {
                    advance()
                    writeLineBreak(depth: depth)
                    output.append(close)
                    return
                } else {
                    let closeText = String(close)
                    throw expected(String(localized: "“,” or “\(closeText)”", bundle: .module,
                                          comment: "JSON error: what was expected, e.g. “,” or “}”"))
                }
            }
        }

        private mutating func copyString() throws {
            let start = (line, column)
            advance()   // opening quote
            output.append("\"")
            while let scalar = current {
                switch scalar {
                case "\"":
                    advance()
                    output.append(scalar)
                    return
                case "\\":
                    let escapeStart = (line, column)   // errors point at the backslash
                    output.append(scalar)
                    advance()
                    guard let escaped = current else { break }
                    switch escaped {
                    case "\"", "\\", "/", "b", "f", "n", "r", "t":
                        output.append(escaped)
                        advance()
                    case "u":
                        output.append(escaped)
                        advance()
                        for _ in 0..<4 {
                            guard let hex = current, hex.properties.isASCIIHexDigit else {
                                throw error(String(localized: "Invalid \\u escape: expected 4 hexadecimal digits.",
                                                   bundle: .module, comment: "JSON error"))
                            }
                            output.append(hex)
                            advance()
                        }
                    default:
                        throw TransformError(String(localized: "Invalid escape sequence “\\\(String(escaped))”.",
                                                    bundle: .module, comment: "JSON error"),
                                             line: escapeStart.0, column: escapeStart.1)
                    }
                default:
                    if scalar.value < 0x20 {
                        throw error(String(localized: "Line breaks and control characters must be escaped in strings.",
                                           bundle: .module, comment: "JSON error"))
                    }
                    output.append(scalar)
                    advance()
                }
            }
            throw TransformError(String(localized: "The string is never closed.", bundle: .module, comment: "JSON error"),
                                 line: start.0, column: start.1)
        }

        /// Copies a number exactly as written after checking it against the JSON grammar:
        /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
        private mutating func copyNumber() throws {
            // Reported where the number goes wrong, e.g. at the "]" in "[1.]".
            func invalid() -> TransformError {
                error(String(localized: "Invalid number.", bundle: .module, comment: "JSON error"))
            }
            if current == "-" { copyCurrent() }
            if current == "0" {
                copyCurrent()
            } else if let digit = current, ("1"..."9").contains(digit) {
                while let digit = current, ("0"..."9").contains(digit) { copyCurrent() }
            } else {
                throw invalid()
            }
            if current == "." {
                copyCurrent()
                guard let digit = current, ("0"..."9").contains(digit) else { throw invalid() }
                while let digit = current, ("0"..."9").contains(digit) { copyCurrent() }
            }
            if current == "e" || current == "E" {
                copyCurrent()
                if current == "+" || current == "-" { copyCurrent() }
                guard let digit = current, ("0"..."9").contains(digit) else { throw invalid() }
                while let digit = current, ("0"..."9").contains(digit) { copyCurrent() }
            }
        }

        private mutating func copyLiteral(_ literal: String) throws {
            for expected in literal.unicodeScalars {
                guard current == expected else {
                    throw error(String(localized: "Unknown word: expected “\(literal)”.", bundle: .module, comment: "JSON error"))
                }
                copyCurrent()
            }
        }

        // MARK: Whitespace and output

        private mutating func writeLineBreak(depth: Int) {
            guard pretty else { return }
            appendNewline()
            for _ in 0..<depth {
                for scalar in indentScalars { output.append(scalar) }
            }
        }

        // One scalar at a time: `UnicodeScalarView.append(contentsOf:)` turned out to copy the
        // whole output on every call, which made formatting a few MB take minutes.
        private mutating func appendNewline() {
            for scalar in newlineScalars { output.append(scalar) }
        }

        /// JSON whitespace is space, tab, LF and CR; anything else is an error.
        private mutating func skipWhitespace() {
            while let scalar = current, scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                advance()
            }
        }

        // MARK: Reading

        private var current: Unicode.Scalar? {
            position < scalars.count ? scalars[position] : nil
        }

        private mutating func copyCurrent() {
            if let scalar = current { output.append(scalar) }
            advance()
        }

        /// Moves to the next character, counting lines ("\r\n" is one break) and columns.
        private mutating func advance() {
            guard position < scalars.count else { return }
            let scalar = scalars[position]
            position += 1
            if scalar == "\n" || (scalar == "\r" && current != "\n") {
                line += 1
                column = 1
            } else if scalar != "\r" {
                column += 1
            }
        }

        // MARK: Errors

        private func error(_ message: String) -> TransformError {
            TransformError(message, line: line, column: column)
        }

        private func expected(_ what: String) -> TransformError {
            if let scalar = current {
                return error(String(localized: "Expected \(what) but found “\(String(scalar))”.", bundle: .module,
                                    comment: "JSON error"))
            }
            return error(String(localized: "Expected \(what) but the text ended.", bundle: .module, comment: "JSON error"))
        }

        private func unexpected(_ scalar: Unicode.Scalar) -> TransformError {
            error(String(localized: "Unexpected character “\(String(scalar))”.", bundle: .module, comment: "JSON error"))
        }
    }
}
