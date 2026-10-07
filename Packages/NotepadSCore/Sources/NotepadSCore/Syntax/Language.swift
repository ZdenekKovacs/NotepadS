import Foundation

/// A language NotepadS can highlight.
public enum Language: String, CaseIterable, Hashable, Sendable {
    case plainText
    case c
    case cpp
    case css
    case diff
    case dockerfile
    case go
    case html
    case ini
    case java
    case javaScript
    case json
    case makefile
    case markdown
    case php
    case python
    case ruby
    case rust
    case shell
    case sql
    case swift
    case toml
    case typeScript
    case xml
    case yaml

    /// The grammar, or nil for plain text.
    public var grammar: Grammar? {
        switch self {
        case .plainText: return nil
        case .css: return .css
        case .diff: return .diff
        case .dockerfile: return .dockerfile
        case .go: return .go
        case .ini: return .ini
        case .java: return .java
        case .makefile: return .makefile
        case .php: return .php
        case .ruby: return .ruby
        case .rust: return .rust
        case .sql: return .sql
        case .swift: return .swift
        case .toml: return .toml
        case .c: return .c
        case .cpp: return .cpp
        case .html: return .html
        case .javaScript: return .javaScript
        case .typeScript: return .typeScript
        case .xml: return .xml
        case .yaml: return .yaml
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
        case .css: return "CSS"
        case .diff: return "Diff"
        case .dockerfile: return "Dockerfile"
        case .go: return "Go"
        case .ini: return "INI"
        case .java: return "Java"
        case .makefile: return "Makefile"
        case .php: return "PHP"
        case .ruby: return "Ruby"
        case .rust: return "Rust"
        case .sql: return "SQL"
        case .swift: return "Swift"
        case .toml: return "TOML"
        case .c: return "C"
        case .cpp: return "C++"
        case .html: return "HTML"
        case .javaScript: return "JavaScript"
        case .typeScript: return "TypeScript"
        case .xml: return "XML"
        case .yaml: return "YAML"
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
        if program == "node" || program == "deno" || program == "bun" {
            return .javaScript
        }
        if program.hasPrefix("ruby") {
            return .ruby
        }
        if program == "php" {
            return .php
        }
        return ["sh", "bash", "zsh", "ksh", "dash"].contains(program) ? .shell : nil
    }

    /// File extensions (lowercase, without the dot) recognized as this language, the usual one
    /// first; that one is suggested when saving. Plain text lists "txt", although every file
    /// without a recognized extension is plain text anyway.
    public var fileExtensions: [String] {
        switch self {
        case .plainText: return ["txt"]
        case .json: return ["json", "geojson", "webmanifest"]
        case .markdown: return ["md", "markdown", "mdown", "mkd"]
        case .python: return ["py", "pyw", "pyi"]
        case .shell: return ["sh", "bash", "zsh", "ksh", "command"]
        case .yaml: return ["yml", "yaml"]
        case .javaScript: return ["js", "mjs", "cjs", "jsx"]
        case .typeScript: return ["ts", "tsx", "mts", "cts"]
        // ".h" could be C or C++; C highlighting is a safe subset for both.
        case .c: return ["c", "h"]
        case .cpp: return ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "ino"]
        case .html: return ["html", "htm", "xhtml"]
        case .xml: return ["xml", "plist", "svg", "xsd", "xsl", "xslt", "rss",
                           "atom", "xib", "storyboard", "csproj", "entitlements"]
        case .css: return ["css", "scss", "less"]
        case .sql: return ["sql"]
        case .swift: return ["swift"]
        case .java: return ["java"]
        case .go: return ["go"]
        case .rust: return ["rs"]
        case .php: return ["php", "phtml"]
        case .ruby: return ["rb", "rake", "gemspec"]
        case .toml: return ["toml"]
        case .ini: return ["ini", "cfg", "conf", "properties"]
        case .makefile: return ["mk", "mak"]
        case .dockerfile: return ["dockerfile", "containerfile"]
        case .diff: return ["diff", "patch"]
        }
    }

    /// Whole file names (lowercase) recognized as this language, such as "Makefile" or ".zshrc".
    public var fileNames: [String] {
        Self.byFileName.filter { $0.value == self }.keys.sorted()
    }

    /// `name` with `newExtension` (no dot) as its extension, for the Save panel. A recognized
    /// extension is replaced; anything else after a dot is kept as part of the name:
    /// "script.js" → "script.py", "notes.v2" → "notes.v2.py", "Makefile" → "Makefile.mk".
    public static func fileName(_ name: String, withExtension newExtension: String) -> String {
        let nsName = name as NSString
        let base = byExtension[nsName.pathExtension.lowercased()] != nil || nsName.pathExtension.lowercased() == "txt"
            ? nsName.deletingPathExtension
            : name
        return "\(base).\(newExtension)"
    }

    /// Built from `fileExtensions`. Plain text is left out, so a ".txt" file still gets its
    /// language from a `#!` line. (`uniqueKeysWithValues` traps on a duplicate; a test checks.)
    private static let byExtension: [String: Language] = Dictionary(uniqueKeysWithValues:
        allCases.filter { $0 != .plainText }.flatMap { language in language.fileExtensions.map { ($0, language) } })

    /// Files recognized by their whole name (lowercased).
    private static let byFileName: [String: Language] = [
        ".bashrc": .shell, ".bash_profile": .shell, ".bash_login": .shell, ".bash_logout": .shell,
        ".profile": .shell, ".zshrc": .shell, ".zshenv": .shell, ".zprofile": .shell, ".zlogin": .shell,
        ".zlogout": .shell,
        "makefile": .makefile, "gnumakefile": .makefile,
        "dockerfile": .dockerfile, "containerfile": .dockerfile,
        "gemfile": .ruby, "rakefile": .ruby, "podfile": .ruby, "fastfile": .ruby,
        ".editorconfig": .ini, ".gitconfig": .ini, ".npmrc": .ini,
        "cargo.lock": .toml, "pipfile": .toml,
    ]
}
