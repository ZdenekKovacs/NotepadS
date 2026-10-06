import Foundation

/// UPPER, lower, Title Case and the identifier styles camelCase, snake_case and kebab-case.
enum CaseConversion {

    enum IdentifierStyle {
        case camel, snake, kebab
    }

    /// Converts each line to an identifier style. Indentation and trailing spaces stay, so a
    /// column of names can be converted in one go; line breaks are untouched.
    static func identifiers(_ text: String, style: IdentifierStyle, locale: Locale) -> String {
        var lines = TextLines(text)
        for index in lines.lines.indices {
            lines.lines[index].content = convertLine(lines.lines[index].content, style: style, locale: locale)
        }
        return lines.text
    }

    private static func convertLine(_ line: String, style: IdentifierStyle, locale: Locale) -> String {
        let characters = Array(line)
        guard let first = characters.firstIndex(where: { !$0.isWhitespace }),
              let last = characters.lastIndex(where: { !$0.isWhitespace }) else { return line }
        let words = splitIntoWords(characters[first...last])
        guard !words.isEmpty else { return line }

        let converted: String
        switch style {
        case .snake:
            converted = words.map { $0.lowercased(with: locale) }.joined(separator: "_")
        case .kebab:
            converted = words.map { $0.lowercased(with: locale) }.joined(separator: "-")
        case .camel:
            converted = words.enumerated().map { index, word in
                let lower = word.lowercased(with: locale)
                guard index > 0, let initial = lower.first else { return lower }
                return String(initial).uppercased(with: locale) + lower.dropFirst()
            }.joined()
        }
        return String(characters[..<first]) + converted + String(characters[(last + 1)...])
    }

    /// Splits text into words at spaces and punctuation, and inside identifiers at case changes:
    /// "getHTTPResponse2Code" → ["get", "HTTP", "Response2", "Code"]. Digits stay with the
    /// word before them ("utf8", "version2").
    static func splitIntoWords(_ characters: ArraySlice<Character>) -> [String] {
        var words: [String] = []
        var current = ""
        let items = Array(characters)
        for (index, character) in items.enumerated() {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if let previous = current.last, character.isUppercase {
                let next = index + 1 < items.count ? items[index + 1] : nil
                // "aB" or "2B": a new word starts at the capital.
                let afterLowerOrDigit = previous.isLowercase || previous.isNumber
                // "HTTPServer": the last capital of a run starts a new word when a lowercase follows.
                let endsAcronym = previous.isUppercase && (next?.isLowercase ?? false)
                if afterLowerOrDigit || endsAcronym {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
