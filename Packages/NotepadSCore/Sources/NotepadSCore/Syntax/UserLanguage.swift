import Foundation

/// A language the user defined in Settings › Languages (like Notepad++'s User Defined Language):
/// keywords, comments, strings and numbers. It becomes a `Grammar` like the built-in ones, but
/// is deliberately simple: no nested blocks and no regular expressions, so any input is valid.
public struct UserLanguage: Codable, Hashable, Identifiable, Sendable {

    /// A list of words colored alike, e.g. keywords or constants.
    public struct KeywordGroup: Codable, Hashable, Sendable {
        /// The words, separated by spaces or line breaks in the Settings field.
        public var words: [String]
        /// Which color of the theme they get.
        public var scope: SyntaxScope

        public init(words: [String] = [], scope: SyntaxScope) {
            self.words = words
            self.scope = scope
        }
    }

    /// The colors a keyword group can choose, in the order Settings lists them; each has its
    /// own color in the theme. New languages give their groups the first four.
    public static let keywordScopes: [SyntaxScope] = [.keyword, .constant, .function, .strong, .variable, .emphasis]
    /// Settings shows this many keyword groups.
    public static let keywordGroupCount = 4

    public var id: UUID
    public var name: String
    /// Lowercase, without the dot.
    public var fileExtensions: [String]
    public var keywordGroups: [KeywordGroup]
    /// Starts a comment that runs to the end of the line, e.g. "#" or "//"; empty for none.
    public var lineComment: String
    /// A comment that may span lines, e.g. "/*" … "*/"; both empty for none.
    public var blockCommentStart: String
    public var blockCommentEnd: String
    /// Each character starts and ends a string, e.g. `"'`. Strings end at the end of the line.
    public var stringDelimiters: String
    /// Inside a string, this character and the one after it are an escape, e.g. `\`; empty for none.
    public var escapeCharacter: String
    /// "BEGIN", "Begin" and "begin" are the same keyword.
    public var ignoresCase: Bool
    public var highlightsNumbers: Bool

    public init(id: UUID = UUID(), name: String, fileExtensions: [String] = [],
                keywordGroups: [KeywordGroup] = UserLanguage.keywordScopes.prefix(UserLanguage.keywordGroupCount).map { KeywordGroup(scope: $0) },
                lineComment: String = "", blockCommentStart: String = "", blockCommentEnd: String = "",
                stringDelimiters: String = "\"", escapeCharacter: String = "\\",
                ignoresCase: Bool = false, highlightsNumbers: Bool = true) {
        self.id = id
        self.name = name
        self.fileExtensions = fileExtensions
        self.keywordGroups = keywordGroups
        self.lineComment = lineComment
        self.blockCommentStart = blockCommentStart
        self.blockCommentEnd = blockCommentEnd
        self.stringDelimiters = stringDelimiters
        self.escapeCharacter = escapeCharacter
        self.ignoresCase = ignoresCase
        self.highlightsNumbers = highlightsNumbers
    }

    // MARK: - Grammar

    /// The highlighting rules. Every piece of user text is escaped, so the patterns are always
    /// valid. Order matters (earliest match wins, ties go to the first rule): comments before
    /// strings, so a quote inside a comment doesn't start a string, and the other way round.
    public var grammar: Grammar {
        var rules: [Rule] = []
        let blockStart = blockCommentStart.trimmingCharacters(in: .whitespaces)
        let blockEnd = blockCommentEnd.trimmingCharacters(in: .whitespaces)
        if !blockStart.isEmpty, !blockEnd.isEmpty {
            rules.append(.span(Self.literal(blockStart), Self.literal(blockEnd), .comment))
        }
        let line = lineComment.trimmingCharacters(in: .whitespaces)
        if !line.isEmpty {
            rules.append(.match(Self.literal(line) + ".*$", .comment))
        }
        let escape = escapeCharacter.first.map { [Rule.match(Self.literal(String($0)) + ".", .stringEscape)] } ?? []
        for delimiter in Self.uniqueCharacters(stringDelimiters) {
            let quote = Self.literal(String(delimiter))
            rules.append(.span(quote, "\(quote)|$", .string, rules: escape))
        }
        for group in keywordGroups {
            let words = Self.uniqueWords(group.words)
            guard !words.isEmpty else { continue }
            // Longest first, so "elseif" isn't colored as "else" + "if". Words may start or end
            // with symbols ("#define", "@media"), which `\b` wouldn't handle; these look-arounds do.
            let alternatives = words.sorted { $0.count > $1.count }.map(Self.literal).joined(separator: "|")
            rules.append(.match("\(ignoresCase ? "(?i)" : "")(?<![\\w])(?:\(alternatives))(?![\\w])", group.scope))
        }
        if highlightsNumbers {
            rules.append(.match(#"\b(?:0[xX][\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number))
        }
        return Grammar(name: name, rules: rules)
    }

    private static func literal(_ text: String) -> String {
        NSRegularExpression.escapedPattern(for: text)
    }

    private static func uniqueCharacters(_ text: String) -> [Character] {
        var seen = Set<Character>()
        return text.filter { !$0.isWhitespace && seen.insert($0).inserted }.map { $0 }
    }

    private static func uniqueWords(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Words and extensions as typed in Settings

    /// Words from a text field: separated by spaces, tabs or line breaks (any style).
    public static func words(from text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
    }

    /// Extensions from a text field: "cfg .mylog, TXT2" → ["cfg", "mylog", "txt2"].
    public static func fileExtensions(from text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map { $0.drop(while: { $0 == "." || $0 == "*" }).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: - Saving and sharing

    /// The file format for saving and for Export/Import: a JSON array of languages.
    public static func encode(_ languages: [UserLanguage]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(languages)
    }

    /// Reads languages saved by `encode`. Throws `UserLanguageError.unreadable` for anything else.
    public static func decode(_ data: Data) throws -> [UserLanguage] {
        do {
            return try JSONDecoder().decode([UserLanguage].self, from: data)
        } catch {
            throw UserLanguageError.unreadable
        }
    }
}

extension SyntaxScope: Codable {}

/// Why a languages file couldn't be read.
public enum UserLanguageError: Error, Equatable, LocalizedError {
    case unreadable

    public var errorDescription: String? {
        String(localized: "This file doesn’t contain NotepadS languages.", bundle: .module,
               comment: "Import languages: error")
    }

    public var recoverySuggestion: String? {
        String(localized: "Choose a file that was made with Export in Settings › Languages.", bundle: .module,
               comment: "Import languages: error suggestion")
    }
}
