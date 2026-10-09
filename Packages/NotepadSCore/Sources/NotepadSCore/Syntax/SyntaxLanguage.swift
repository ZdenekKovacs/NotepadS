import Foundation

/// The language a document is highlighted with: a built-in one, or one the user defined.
public enum SyntaxLanguage: Hashable, Sendable {
    case builtIn(Language)
    case user(UserLanguage)

    public static let plainText = SyntaxLanguage.builtIn(.plainText)

    public var displayName: String {
        switch self {
        case .builtIn(let language): return language.displayName
        case .user(let language): return language.name
        }
    }

    /// nil for plain text.
    public var grammar: Grammar? {
        switch self {
        case .builtIn(let language): return language.grammar
        case .user(let language): return language.grammar
        }
    }

    public var fileExtensions: [String] {
        switch self {
        case .builtIn(let language): return language.fileExtensions
        case .user(let language): return language.fileExtensions
        }
    }

    /// A stable name for saving a choice (e.g. the Open panel's filter):
    /// "python" for a built-in language, "user:<UUID>" for a user-defined one.
    public var identifier: String {
        switch self {
        case .builtIn(let language): return language.rawValue
        case .user(let language): return "user:\(language.id.uuidString)"
        }
    }

    /// The language with `identifier`, looking up user-defined ones in `userLanguages`.
    public init?(identifier: String, userLanguages: [UserLanguage]) {
        if identifier.hasPrefix("user:") {
            guard let language = userLanguages.first(where: { "user:\($0.id.uuidString)" == identifier }) else { return nil }
            self = .user(language)
        } else {
            guard let language = Language(rawValue: identifier) else { return nil }
            self = .builtIn(language)
        }
    }

    /// For the Open panel's filter: see `Language.includes(fileName:)`. A user-defined language
    /// matches its extensions.
    public func includes(fileName: String) -> Bool {
        switch self {
        case .builtIn(let language):
            return language.includes(fileName: fileName)
        case .user(let language):
            let pathExtension = (fileName.lowercased() as NSString).pathExtension
            return !pathExtension.isEmpty && language.fileExtensions.contains(pathExtension)
        }
    }

    /// The language for a file: a user-defined language with the file's extension wins (so the
    /// user can take over an extension), otherwise `Language.detect`.
    public static func detect(fileName: String?, firstLine: String?, userLanguages: [UserLanguage]) -> SyntaxLanguage {
        if let fileName {
            let pathExtension = (fileName.lowercased() as NSString).pathExtension
            if !pathExtension.isEmpty,
               let language = userLanguages.first(where: { $0.fileExtensions.contains(pathExtension) }) {
                return .user(language)
            }
        }
        return .builtIn(Language.detect(fileName: fileName, firstLine: firstLine))
    }

    /// The same language with its latest definition after the user edited their languages:
    /// a user-defined language is looked up by its ID; nil if it was deleted.
    public func updated(from userLanguages: [UserLanguage]) -> SyntaxLanguage? {
        switch self {
        case .builtIn:
            return self
        case .user(let language):
            return userLanguages.first { $0.id == language.id }.map(SyntaxLanguage.user)
        }
    }
}
