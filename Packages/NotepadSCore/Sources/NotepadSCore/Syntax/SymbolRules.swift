import Foundation

/// The definition patterns of each language for the Function List, tried in order on every line.
extension Language {

    var symbolRules: [SymbolRule] {
        Self.symbolRuleTable[self] ?? []
    }

    /// False for languages without definitions to list (plain text, JSON, HTML …).
    public var hasFunctionList: Bool {
        !symbolRules.isEmpty
    }

    /// Built once: compiling the patterns for every document would be wasted work.
    private static let symbolRuleTable: [Language: [SymbolRule]] = {
        var table: [Language: [SymbolRule]] = [:]
        for language in allCases {
            table[language] = makeSymbolRules(language)
        }
        return table
    }()

    // MARK: - Shared patterns

    /// A C-style function or method definition: optional modifiers and return type, a name,
    /// a parameter list, then nothing but an optional `{` (a call ends with `;`). Lines starting
    /// with a control keyword are not definitions.
    private static let cStyleFunction = SymbolRule(
        #"^\s*(?!(?:if|for|foreach|while|switch|catch|return|else|do|sizeof|new|delete|throw|case|using|typedef|goto|lock|await|yield)\b)(?:[\w:<>,\*&\[\]~@.?]+\s+)*?[\*&]*(?<name>~?[A-Za-z_][\w:]*)\s*\([^;{}]*\)?\s*(?:const\s*)?(?:noexcept\s*)?(?:override\s*)?(?:throws\s+[\w., ]+\s*)?(?:->\s*[\w:<>\*&]+\s*)?(?:where\s+[^{]+)?\{?\s*$"#,
        .function)

    private static let cStyleTypes = SymbolRule(
        #"\b(?:class|interface|enum|struct|record|union|namespace|trait|object)\s+(?<name>[A-Za-z_]\w*)(?!\s*;)"#, .type)

    private static func makeSymbolRules(_ language: Language) -> [SymbolRule] {
        switch language {
        case .plainText, .json, .html, .xml, .diff, .smalltalk:
            return []
        case .swift:
            return [
                SymbolRule(#"\bfunc\s+(?<name>[^\s(<]+)"#, .function),
                SymbolRule(#"^\s*(?:[\w@()]+\s+)*(?<name>init|deinit)\s*[?!]?\s*[(<{]"#, .function),
                SymbolRule(#"\b(?:class|struct|enum|protocol|extension|actor)\s+(?!func\b|var\b|let\b)(?<name>[A-Za-z_][\w.]*)"#, .type),
            ]
        case .python:
            return [
                SymbolRule(#"^\s*(?:async\s+)?def\s+(?<name>\w+)"#, .function),
                SymbolRule(#"^\s*class\s+(?<name>\w+)"#, .type),
            ]
        case .javaScript, .typeScript:
            return [
                SymbolRule(#"\bfunction\b\s*\*?\s*(?<name>[\w$]+)\s*[(<]"#, .function),
                SymbolRule(#"\b(?:class|interface|enum|namespace)\s+(?<name>[\w$]+)"#, .type),
                SymbolRule(#"^\s*type\s+(?<name>\w+)\s*(?:<[^>]*>)?\s*="#, .type),
                SymbolRule(#"^\s*(?:export\s+)?(?:const|let|var)\s+(?<name>[\w$]+)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::\s*[^=]+)?=>|[\w$]+\s*=>)"#, .function),
                SymbolRule(#"^\s*(?:(?:public|private|protected|static|async|get|set|readonly|override|abstract)\s+)*(?!(?:if|for|while|switch|catch|function|return)\b)(?<name>[\w$]+)\s*\([^;]*\)\s*(?::\s*[^{=;]+)?\{\s*$"#, .function),
            ]
        case .c, .cpp, .java, .csharp, .d:
            return [cStyleTypes, cStyleFunction]
        case .objectiveC:
            return [
                SymbolRule(#"^\s*[-+]\s*\([^)]*\)\s*(?<name>\w+)"#, .function),
                SymbolRule(#"^\s*@(?:interface|implementation|protocol)\s+(?<name>\w+)"#, .type),
                cStyleTypes, cStyleFunction,
            ]
        case .kotlin:
            return [
                SymbolRule(#"\bfun\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?(?<name>\w+)"#, .function),
                cStyleTypes,
            ]
        case .scala:
            return [SymbolRule(#"\bdef\s+(?<name>\w+)"#, .function), cStyleTypes]
        case .groovy, .dart:
            return [cStyleTypes, SymbolRule(#"^\s*def\s+(?<name>\w+)\s*\("#, .function), cStyleFunction]
        case .go:
            return [
                SymbolRule(#"^\s*func\s+(?:\([^)]*\)\s*)?(?<name>\w+)"#, .function),
                SymbolRule(#"^\s*type\s+(?<name>\w+)\s+(?:struct|interface)\b"#, .type),
            ]
        case .rust:
            return [
                SymbolRule(#"\bfn\s+(?<name>\w+)"#, .function),
                SymbolRule(#"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:struct|enum|trait|mod|union)\s+(?<name>\w+)"#, .type),
                SymbolRule(#"^\s*impl(?:<[^>]*>)?\s+(?<name>[\w:<>, ]+?)\s*(?:\{|$|where\b)"#, .type),
            ]
        case .php:
            return [
                SymbolRule(#"\bfunction\s+&?(?<name>\w+)"#, .function),
                SymbolRule(#"\b(?:class|interface|trait|enum)\s+(?<name>\w+)"#, .type),
            ]
        case .ruby:
            return [
                SymbolRule(#"^\s*def\s+(?<name>[\w.]+[?!=]?)"#, .function),
                SymbolRule(#"^\s*(?:class|module)\s+(?<name>[\w:]+)"#, .type),
            ]
        case .shell:
            return [
                SymbolRule(#"^\s*function\s+(?<name>[\w.:-]+)"#, .function),
                SymbolRule(#"^\s*(?<name>[\w.:-]+)\s*\(\s*\)"#, .function),
            ]
        case .lua:
            return [
                SymbolRule(#"\bfunction\s+(?<name>[\w.:]+)"#, .function),
                SymbolRule(#"^\s*(?:local\s+)?(?<name>[\w.:]+)\s*=\s*function\b"#, .function),
            ]
        case .perl:
            return [
                SymbolRule(#"^\s*sub\s+(?<name>\w+)"#, .function),
                SymbolRule(#"^\s*package\s+(?<name>[\w:]+)"#, .type),
            ]
        case .powerShell:
            return [
                SymbolRule(#"^\s*(?:function|filter)\s+(?<name>[\w-]+)"#, .function, ignoringCase: true),
                SymbolRule(#"^\s*class\s+(?<name>\w+)"#, .type, ignoringCase: true),
            ]
        case .batch:
            return [SymbolRule(#"^\s*:(?!:)(?<name>[^\s:]+)"#, .section)]
        case .visualBasic:
            return [
                SymbolRule(#"^\s*(?:(?:public|private|friend|protected|shared|static|overrides|overridable|mustoverride|async)\s+)*(?:sub|function|property)\s+(?:(?:get|let|set)\s+)?(?<name>\w+)"#, .function, ignoringCase: true),
                SymbolRule(#"^\s*(?:(?:public|private|friend|protected|partial)\s+)*(?:class|module|structure|interface|enum)\s+(?<name>\w+)"#, .type, ignoringCase: true),
            ]
        case .autoIt:
            return [SymbolRule(#"^\s*func\s+(?<name>\w+)"#, .function, ignoringCase: true)]
        case .nsis:
            return [SymbolRule(#"^\s*(?:function|section|sectiongroup)\s+(?:/o\s+)?"?(?<name>[^"\s]+)"#, .function, ignoringCase: true)]
        case .innoSetup:
            return [
                SymbolRule(#"^\s*\[(?<name>[^\]]+)\]"#, .section),
                SymbolRule(#"^\s*(?:procedure|function)\s+(?<name>\w+)"#, .function, ignoringCase: true),
            ]
        case .registry:
            return [SymbolRule(#"^\s*\[-?(?<name>[^\]]+)\]"#, .section)]
        case .ini, .toml:
            return [SymbolRule(#"^\s*\[\[?(?<name>[^\]]+)\]"#, .section)]
        case .yaml:
            return [SymbolRule(#"^(?<name>[\w.\-]+)\s*:(?:\s|$)"#, .section)]
        case .css:
            return [SymbolRule(#"^\s*(?<name>[^\s{}@/;][^{};]*?)\s*\{"#, .section)]
        case .sql:
            return [SymbolRule(#"\bcreate\s+(?:or\s+replace\s+)?(?:function|procedure|view|table|trigger|index)\s+(?:if\s+not\s+exists\s+)?(?<name>[\w."`\[\]]+)"#, .function, ignoringCase: true)]
        case .makefile:
            return [SymbolRule(#"^(?<name>[^\s:#=][^:=#]*?)\s*::?(?!=)"#, .section)]
        case .dockerfile:
            return [SymbolRule(#"^\s*from\s+\S+\s+as\s+(?<name>\S+)"#, .section, ignoringCase: true)]
        case .cmake:
            return [SymbolRule(#"^\s*(?:function|macro)\s*\(\s*(?<name>[\w-]+)"#, .function, ignoringCase: true)]
        case .markdown:
            return [SymbolRule(#"^\s{0,3}(?<level>#{1,6})\s+(?<name>.+?)\s*#*\s*$"#, .heading)]
        case .latex:
            return [SymbolRule(#"\\(?<level>part|chapter|section|subsection|subsubsection|paragraph)\*?\s*\{(?<name>[^}]*)\}"#, .heading)]
        case .r:
            return [SymbolRule(#"^\s*(?<name>[\w.]+)\s*(?:<-|=)\s*function\b"#, .function)]
        case .tcl:
            return [SymbolRule(#"^\s*proc\s+(?<name>\S+)"#, .function)]
        case .coffeeScript:
            return [
                SymbolRule(#"^\s*class\s+(?<name>[\w$.]+)"#, .type),
                SymbolRule(#"^\s*(?<name>[\w$.@]+)\s*[:=]\s*(?:\([^)]*\)\s*)?[-=]>"#, .function),
            ]
        case .haskell:
            return [
                SymbolRule(#"^(?<name>[a-z_][\w']*)\s*::"#, .function),
                SymbolRule(#"^(?:data|newtype|type|class)\s+(?<name>[A-Z][\w']*)"#, .type),
            ]
        case .erlang:
            return [SymbolRule(#"^(?<name>[a-z]\w*)\s*\("#, .function)]
        case .lisp:
            return [SymbolRule(#"\(def(?:un|macro|ine|n|method|generic|var|parameter)\s+\(?(?<name>[^\s()]+)"#, .function)]
        case .ocaml:
            return [
                SymbolRule(#"^\s*(?:let|and)\s+(?:rec\s+)?(?<name>[a-z_][\w']*)"#, .function),
                SymbolRule(#"^\s*(?:module|type)\s+(?:type\s+)?(?<name>\w+)"#, .type),
            ]
        case .matlab:
            return [SymbolRule(#"^\s*function\s+(?:(?:\[[^\]]*\]|\w+)\s*=\s*)?(?<name>\w+)"#, .function)]
        case .fortran:
            return [SymbolRule(#"^\s*(?:(?:pure|elemental|recursive|module|integer|real|logical|character|double\s+precision|complex)(?:\([^)]*\))?\s+)*(?:subroutine|function|program|module)\s+(?!procedure\b)(?<name>\w+)"#, .function, ignoringCase: true)]
        case .postScript:
            return [SymbolRule(#"^\s*/(?<name>[^\s/{}\[\]()]+)\s*\{"#, .function)]
        case .pascal:
            return [SymbolRule(#"^\s*(?:class\s+)?(?:procedure|function|constructor|destructor)\s+(?<name>[\w.]+)"#, .function, ignoringCase: true)]
        case .cobol:
            return [SymbolRule(#"^\s*(?<name>[\w-]+)\s+(?:section|division)\s*\."#, .section, ignoringCase: true)]
        case .ada:
            return [SymbolRule(#"^\s*(?:overriding\s+)?(?:procedure|function|package(?:\s+body)?|task(?:\s+body)?)\s+(?<name>[\w.]+)"#, .function, ignoringCase: true)]
        case .assembly:
            return [SymbolRule(#"^(?<name>[A-Za-z_.$][\w.$@]*):"#, .section)]
        case .verilog:
            return [
                SymbolRule(#"^\s*(?:module|interface|package|program)\s+(?<name>\w+)"#, .type),
                SymbolRule(#"^\s*(?:function|task)\s+(?:automatic\s+)?(?:[\w\[\]:]+\s+)*?(?<name>\w+)\s*[(;]"#, .function),
            ]
        case .vhdl:
            return [
                SymbolRule(#"^\s*(?:entity|architecture|package(?:\s+body)?)\s+(?<name>\w+)"#, .type, ignoringCase: true),
                SymbolRule(#"^\s*(?:pure\s+|impure\s+)?(?:function|procedure)\s+(?<name>\w+)"#, .function, ignoringCase: true),
            ]
        }
    }
}
