import Foundation

/// Base64 (RFC 4648) and URL percent-encoding (RFC 3986) of text as UTF-8.
enum Codecs {

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    /// Accepts line-wrapped input, missing `=` padding and the URL-safe alphabet (`-`, `_`).
    static func base64Decode(_ text: String, context: TransformContext) throws -> String {
        var cleaned = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        cleaned = cleaned.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = cleaned.utf8.count % 4
        if remainder == 2 || remainder == 3 {
            cleaned += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: cleaned) else {
            throw TransformError(String(localized: "The text isn’t valid Base64.", bundle: .module,
                                        comment: "Base64 decode error"))
        }
        return try decodedText(data, context: context)
    }

    /// Percent-encodes everything except the RFC 3986 unreserved characters
    /// (`A–Z a–z 0–9 - . _ ~`), so the result is safe anywhere in a URL.
    static func urlEncode(_ text: String) -> String {
        // `addingPercentEncoding` only returns nil for text that isn't valid Unicode, which a
        // Swift String always is; keep the text unchanged in that impossible case.
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    static func urlDecode(_ text: String, context: TransformContext) throws -> String {
        guard let decoded = text.removingPercentEncoding else {
            throw TransformError(String(localized: "The text contains an invalid percent escape, or the decoded bytes aren’t UTF-8 text.",
                                        bundle: .module, comment: "URL decode error"))
        }
        return LineEnding.convertAll(decoded, to: context.lineEnding)
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Decoded bytes become text only if they are UTF-8; line breaks in it are new to the
    /// document, so they get its style.
    private static func decodedText(_ data: Data, context: TransformContext) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw TransformError(String(localized: "The decoded data isn’t UTF-8 text.", bundle: .module,
                                        comment: "Decode error"))
        }
        return LineEnding.convertAll(text, to: context.lineEnding)
    }
}
