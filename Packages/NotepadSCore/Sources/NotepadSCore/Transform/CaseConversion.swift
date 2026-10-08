import Foundation

/// UPPER, lower, Title Case, Sentence case, iNVERT and rAnDoM case, and the identifier styles
/// camelCase, snake_case and kebab-case. Only letters change, so line breaks always stay.
enum CaseConversion {

    /// Upper-cases the first letter of every word and leaves the other letters as they are
    /// ("an HTTP server" → "An HTTP Server"); Notepad++'s "Proper Case (blend)". A word starts
    /// at a letter that doesn't follow a letter, digit or apostrophe ("don't" stays one word).
    static func titleCaseKeepingOtherLetters(_ text: String, locale: Locale) -> String {
        var result = ""
        var previous: Character?
        for character in text {
            let isWordStart = character.isLetter && !(previous.map(continuesWord) ?? false)
            result += isWordStart ? String(character).capitalized(with: locale) : String(character)
            previous = character
        }
        return result
    }

    /// Upper-cases the first letter of every sentence; the other letters become lower case, or
    /// stay as they are with `keepingOtherLetters` ("Sentence case (blend)" in Notepad++).
    /// A sentence starts the text, or follows ".", "!" or "?" and a space or line break, so
    /// "2.0" and "e.g." in the middle of a word don't start one.
    static func sentenceCase(_ text: String, keepingOtherLetters: Bool, locale: Locale) -> String {
        var result = ""
        var isSentenceStart = true
        var followsSentenceEnd = false   // after ".", "!" or "?", waiting for a space
        for character in text {
            if character.isLetter {
                result += isSentenceStart ? String(character).capitalized(with: locale)
                    : keepingOtherLetters ? String(character) : String(character).lowercased(with: locale)
                isSentenceStart = false
                followsSentenceEnd = false
                continue
            }
            result.append(character)
            if character == "." || character == "!" || character == "?" {
                followsSentenceEnd = true
            } else if character.isWhitespace {   // also "\r\n", which is one Character
                if followsSentenceEnd { isSentenceStart = true }
            } else if character.isNumber {
                isSentenceStart = false
                followsSentenceEnd = false
            } else {
                followsSentenceEnd = false   // quotes and brackets keep a pending sentence start
            }
        }
        return result
    }

    /// Swaps upper and lower case: "Hello" → "hELLO".
    static func invertCase(_ text: String, locale: Locale) -> String {
        var result = ""
        for character in text {
            if character.isUppercase {
                result += String(character).lowercased(with: locale)
            } else if character.isLowercase {
                result += String(character).uppercased(with: locale)
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Makes each letter upper or lower case at random. Tests pass a seeded generator.
    static func randomCase(_ text: String, locale: Locale, using generator: inout some RandomNumberGenerator) -> String {
        var result = ""
        for character in text {
            guard character.isLetter else {
                result.append(character)
                continue
            }
            result += Bool.random(using: &generator) ? String(character).uppercased(with: locale)
                                                     : String(character).lowercased(with: locale)
        }
        return result
    }

    /// True if a letter after `character` is inside a word, not at its start.
    private static func continuesWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "\u{2019}"
    }

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
