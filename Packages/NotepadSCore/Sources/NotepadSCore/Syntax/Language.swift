import Foundation

/// A language NotepadS can highlight.
public enum Language: String, CaseIterable, Hashable, Sendable {
    case plainText
    case json
    case markdown
    case python
    case shell

    /// The grammar, or nil for plain text.
    public var grammar: Grammar? {
        switch self {
        case .plainText: return nil
        case .json: return .json
        case .markdown: return .markdown
        case .python: return .python
        case .shell: return .shell
        }
    }

    /// Name for the status bar and menus.
    public var displayName: String {
        switch self {
        case .plainText:
            return String(localized: "Plain Text", bundle: .module, comment: "Language name: no highlighting")
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .python: return "Python"
        case .shell: return "Shell"
        }
    }

    // MARK: - Detection

    /// Guesses the language from the file name, then from a `#!` line.
    ///
    /// - Parameters:
    ///   - fileName: the file's name, e.g. "setup.py" or ".zshrc"; nil for untitled documents.
    ///   - firstLine: the first line of the text (only its `#!` line is used).
    public static func detect(fileName: String?, firstLine: String?) -> Language {
        if let fileName, let language = fromFileName(fileName) {
            return language
        }
        if let firstLine, let language = fromShebang(firstLine) {
            return language
        }
        return .plainText
    }

    static func fromFileName(_ fileName: String) -> Language? {
        let name = fileName.lowercased()
        if let language = byFileName[name] {
            return language
        }
        let pathExtension = (name as NSString).pathExtension
        return pathExtension.isEmpty ? nil : byExtension[pathExtension]
    }

    /// `#!/bin/bash`, `#!/usr/bin/env python3`, `#!/usr/bin/env -S zsh -f` …
    static func fromShebang(_ line: String) -> Language? {
        guard line.hasPrefix("#!") else { return nil }
        let words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard var program = words.first.map({ ($0 as NSString).lastPathComponent }) else { return nil }
        if program == "env" {
            // The interpreter is the first argument of env that isn't an option.
            guard let argument = words.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
            program = (argument as NSString).lastPathComponent
        }
        if program.hasPrefix("python") {
            return .python
        }
        return ["sh", "bash", "zsh", "ksh", "dash"].contains(program) ? .shell : nil
    }

    private static let byExtension: [String: Language] = [
        "json": .json, "geojson": .json, "webmanifest": .json,
        "md": .markdown, "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
        "py": .python, "pyw": .python, "pyi": .python,
        "sh": .shell, "bash": .shell, "zsh": .shell, "ksh": .shell, "command": .shell,
    ]

    /// Files recognized by their whole name (lowercased).
    private static let byFileName: [String: Language] = [
        ".bashrc": .shell, ".bash_profile": .shell, ".bash_login": .shell, ".bash_logout": .shell,
        ".profile": .shell, ".zshrc": .shell, ".zshenv": .shell, ".zprofile": .shell, ".zlogin": .shell,
        ".zlogout": .shell,
    ]
}
