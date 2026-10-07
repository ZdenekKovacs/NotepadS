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
    case csharp
    case visualBasic
    case powerShell
    case batch
    case registry
    case autoIt
    case nsis
    case innoSetup
    case kotlin
    case scala
    case groovy
    case dart
    case objectiveC
    case lua
    case perl
    case r
    case tcl
    case coffeeScript
    case haskell
    case erlang
    case lisp
    case ocaml
    case smalltalk
    case matlab
    case fortran
    case latex
    case postScript
    case cmake
    case pascal
    case cobol
    case ada
    case assembly
    case d
    case verilog
    case vhdl

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
        case .csharp: return .csharp
        case .visualBasic: return .visualBasic
        case .powerShell: return .powerShell
        case .batch: return .batch
        case .registry: return .registry
        case .autoIt: return .autoIt
        case .nsis: return .nsis
        case .innoSetup: return .innoSetup
        case .kotlin: return .kotlin
        case .scala: return .scala
        case .groovy: return .groovy
        case .dart: return .dart
        case .objectiveC: return .objectiveC
        case .lua: return .lua
        case .perl: return .perl
        case .r: return .r
        case .tcl: return .tcl
        case .coffeeScript: return .coffeeScript
        case .haskell: return .haskell
        case .erlang: return .erlang
        case .lisp: return .lisp
        case .ocaml: return .ocaml
        case .smalltalk: return .smalltalk
        case .matlab: return .matlab
        case .fortran: return .fortran
        case .latex: return .latex
        case .postScript: return .postScript
        case .cmake: return .cmake
        case .pascal: return .pascal
        case .cobol: return .cobol
        case .ada: return .ada
        case .assembly: return .assembly
        case .d: return .d
        case .verilog: return .verilog
        case .vhdl: return .vhdl
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
        case .csharp: return "C#"
        case .visualBasic: return "Visual Basic"
        case .powerShell: return "PowerShell"
        case .batch: return "Batch"
        case .registry: return "Windows Registry"
        case .autoIt: return "AutoIt"
        case .nsis: return "NSIS"
        case .innoSetup: return "Inno Setup"
        case .kotlin: return "Kotlin"
        case .scala: return "Scala"
        case .groovy: return "Groovy"
        case .dart: return "Dart"
        case .objectiveC: return "Objective-C"
        case .lua: return "Lua"
        case .perl: return "Perl"
        case .r: return "R"
        case .tcl: return "Tcl"
        case .coffeeScript: return "CoffeeScript"
        case .haskell: return "Haskell"
        case .erlang: return "Erlang"
        case .lisp: return "Lisp"
        case .ocaml: return "OCaml"
        case .smalltalk: return "Smalltalk"
        case .matlab: return "MATLAB"
        case .fortran: return "Fortran"
        case .latex: return "LaTeX"
        case .postScript: return "PostScript"
        case .cmake: return "CMake"
        case .pascal: return "Pascal/Delphi"
        case .cobol: return "COBOL"
        case .ada: return "Ada"
        case .assembly: return "Assembly"
        case .d: return "D"
        case .verilog: return "Verilog"
        case .vhdl: return "VHDL"
        }
    }

    // MARK: - Menus

    /// The languages for a menu, without plain text (which menus list on its own): sorted by
    /// name and grouped by first letter, as Notepad++'s Language menu does. With 60 languages
    /// one flat list would be longer than the screen.
    public static var groupedByInitial: [(initial: String, languages: [Language])] {
        let sorted = allCases.filter { $0 != .plainText }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        var groups: [(initial: String, languages: [Language])] = []
        for language in sorted {
            let initial = language.displayName.prefix(1).uppercased()
            if groups.last?.initial == initial {
                groups[groups.count - 1].languages.append(language)
            } else {
                groups.append((initial, [language]))
            }
        }
        return groups
    }

    // MARK: - Detection

    /// Guesses the language from the file name, then from a `#!` line.
    ///
    /// - Parameters:
    ///   - fileName: the file's name, e.g. "setup.py" or ".zshrc"; nil for untitled documents.
    ///   - firstLine: the first line of the text (only its `#!` line is used).
    public static func detect(fileName: String?, firstLine: String?) -> Language {
        if let fileName, let language = fromFileName(fileName) {
            // ".m" is MATLAB or Objective-C. Objective-C files start with a comment, #import or
            // an @ directive; none of those is MATLAB (whose comments start with %).
            if language == .matlab, let firstLine, Self.looksLikeObjectiveC(firstLine) {
                return .objectiveC
            }
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

    private static func looksLikeObjectiveC(_ line: String) -> Bool {
        let start = line.drop(while: { $0 == " " || $0 == "\t" })
        return ["#", "//", "/*", "@"].contains { start.hasPrefix($0) }
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
        if program.hasPrefix("perl") {
            return .perl
        }
        if program.hasPrefix("lua") {
            return .lua
        }
        if program.hasPrefix("tclsh") || program.hasPrefix("wish") {
            return .tcl
        }
        switch program {
        case "pwsh", "powershell": return .powerShell
        case "Rscript": return .r
        case "groovy": return .groovy
        case "escript": return .erlang
        case "coffee": return .coffeeScript
        case "sbcl", "clisp", "guile", "racket": return .lisp
        default: break
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
        case .csharp: return ["cs", "csx"]
        case .visualBasic: return ["vb", "vbs", "bas", "frm"]
        case .powerShell: return ["ps1", "psm1", "psd1"]
        case .batch: return ["bat", "cmd"]
        case .registry: return ["reg"]
        case .autoIt: return ["au3"]
        case .nsis: return ["nsi", "nsh"]
        case .innoSetup: return ["iss"]
        case .kotlin: return ["kt", "kts"]
        case .scala: return ["scala", "sc"]
        case .groovy: return ["groovy", "gradle", "gvy"]
        case .dart: return ["dart"]
        case .objectiveC: return ["m", "mm"]
        case .lua: return ["lua"]
        case .perl: return ["pl", "pm"]
        case .r: return ["r"]
        case .tcl: return ["tcl", "tk"]
        case .coffeeScript: return ["coffee"]
        case .haskell: return ["hs"]
        case .erlang: return ["erl", "hrl"]
        case .lisp: return ["lisp", "lsp", "cl", "el", "scm", "ss", "rkt", "clj", "cljs", "edn"]
        case .ocaml: return ["ml", "mli"]
        case .smalltalk: return ["st"]
        case .matlab: return ["m"]
        case .fortran: return ["f90", "f95", "f03", "f08", "f", "for", "f77"]
        case .latex: return ["tex", "ltx", "sty", "cls"]
        case .postScript: return ["ps", "eps"]
        case .cmake: return ["cmake"]
        case .pascal: return ["pas", "pp", "dpr", "dpk", "lpr"]
        case .cobol: return ["cbl", "cob", "cpy"]
        case .ada: return ["adb", "ads", "ada"]
        case .assembly: return ["asm", "s", "nasm"]
        case .d: return ["d", "di"]
        case .verilog: return ["v", "vh", "sv", "svh"]
        case .vhdl: return ["vhd", "vhdl"]
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
    /// language from a `#!` line. Each extension belongs to one language (a test checks),
    /// except ".m": see `detect`.
    private static let byExtension: [String: Language] = {
        var languages: [String: Language] = [:]
        for language in allCases where language != .plainText {
            for fileExtension in language.fileExtensions where languages[fileExtension] == nil {
                languages[fileExtension] = language
            }
        }
        languages["m"] = .matlab
        return languages
    }()

    /// Extensions that two languages use; `detect` tells them apart by the first line.
    static let sharedExtensions: Set<String> = ["m"]

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
        "cmakelists.txt": .cmake, "jenkinsfile": .groovy,
    ]
}
