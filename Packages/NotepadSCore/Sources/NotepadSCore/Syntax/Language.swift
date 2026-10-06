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

    private static let byExtension: [String: Language] = [
        "json": .json, "geojson": .json, "webmanifest": .json,
        "md": .markdown, "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
        "py": .python, "pyw": .python, "pyi": .python,
        "sh": .shell, "bash": .shell, "zsh": .shell, "ksh": .shell, "command": .shell,
        "yml": .yaml, "yaml": .yaml,
        "js": .javaScript, "mjs": .javaScript, "cjs": .javaScript, "jsx": .javaScript,
        "ts": .typeScript, "tsx": .typeScript, "mts": .typeScript, "cts": .typeScript,
        // ".h" could be C or C++; C highlighting is a safe subset for both.
        "c": .c, "h": .c,
        "cpp": .cpp, "cc": .cpp, "cxx": .cpp, "c++": .cpp, "hpp": .cpp, "hh": .cpp, "hxx": .cpp, "ino": .cpp,
        "html": .html, "htm": .html, "xhtml": .html,
        "xml": .xml, "plist": .xml, "svg": .xml, "xsd": .xml, "xsl": .xml, "xslt": .xml, "rss": .xml,
        "atom": .xml, "xib": .xml, "storyboard": .xml, "csproj": .xml, "entitlements": .xml,
        "css": .css, "scss": .css, "less": .css,
        "sql": .sql,
        "swift": .swift,
        "java": .java,
        "go": .go,
        "rs": .rust,
        "php": .php, "phtml": .php,
        "rb": .ruby, "rake": .ruby, "gemspec": .ruby,
        "toml": .toml,
        "ini": .ini, "cfg": .ini, "conf": .ini, "properties": .ini,
        "mk": .makefile, "mak": .makefile,
        "dockerfile": .dockerfile, "containerfile": .dockerfile,
        "diff": .diff, "patch": .diff,
    ]

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
