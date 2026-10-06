extension Grammar {
    /// Swift.
    public static let swift = Grammar(name: "Swift", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""""#, #"""""#, .string, rules: Grammar.swiftStringRules),
        .span(#"""#, #""|$"#, .string, rules: Grammar.swiftStringRules),
        .match(#"@\w+"#, .function),                                             // @MainActor, @objc
        .match(#"#\w+"#, .keyword),                                              // #if, #available, #selector
        .words(["actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class",
                "continue", "convenience", "default", "defer", "deinit", "do", "dynamic", "else", "enum",
                "extension", "fallthrough", "fileprivate", "final", "for", "func", "get", "guard", "if",
                "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let", "macro",
                "mutating", "nonisolated", "open", "operator", "override", "private", "protocol", "public",
                "repeat", "required", "rethrows", "return", "set", "some", "static", "struct", "subscript",
                "switch", "throw", "throws", "try", "typealias", "unowned", "var", "weak", "where", "while",
                "willSet", "didSet"], .keyword),
        .words(["true", "false", "nil", "self", "Self", "super"], .constant),
        .match(#"\b(?:0x[\da-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    private static let swiftStringRules: [Rule] = [
        .match(#"\\\([^)\n]*\)"#, .variable),                                    // \(interpolation)
        .match(#"\\."#, .stringEscape),
    ]

    /// Java.
    public static let java = Grammar(name: "Java", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""""#, #"""""#, .string, rules: [.match(#"\\."#, .stringEscape)]),   // text blocks
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),
        .match(#"@\w+"#, .function),                                             // annotations
        .words(["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const",
                "continue", "default", "do", "double", "else", "enum", "exports", "extends", "final", "finally",
                "float", "for", "goto", "if", "implements", "import", "instanceof", "int", "interface", "long",
                "module", "native", "new", "package", "permits", "private", "protected", "public", "record",
                "requires", "return", "sealed", "short", "static", "strictfp", "super", "switch",
                "synchronized", "this", "throw", "throws", "transient", "try", "var", "void", "volatile",
                "while", "yield"], .keyword),
        .words(["true", "false", "null"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?)[lLfFdD]?\b"#, .number),
        .match(#"\b[A-Za-z_$][\w$]*(?=\s*\()"#, .function),
    ])

    /// Go.
    public static let go = Grammar(name: "Go", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("`", "`", .string),                                                // raw strings span lines
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),                                // runes
        .words(["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
                "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return",
                "select", "struct", "switch", "type", "var", "any", "bool", "byte", "complex64", "complex128",
                "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string",
                "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"], .keyword),
        .words(["true", "false", "nil", "iota"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|0[oO]?[0-7_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?i?)\b"#,
               .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// Rust.
    public static let rust = Grammar(name: "Rust", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"b?""#, #"""#, .string, rules: [.match(#"\\."#, .stringEscape)]),  // strings may span lines
        .match(#"b?'(?:[^'\\\n]|\\.)'"#, .string),                               // chars: 'a', '\n'
        .match(#"'[A-Za-z_]\w*\b(?!')"#, .variable),                              // lifetimes: 'a, 'static
        .match(#"#!?\[[^\]\n]*\]"#, .keyword),                                    // attributes
        .match(#"\b[A-Za-z_]\w*!"#, .function),                                   // macros: println!
        .match(#"(?<=\bfn\s)[A-Za-z_]\w*"#, .function),                              // fn name<T>(…)
        .words(["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
                "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub",
                "ref", "return", "static", "struct", "super", "trait", "type", "union", "unsafe", "use",
                "where", "while", "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64",
                "u128", "usize", "f32", "f64", "bool", "char", "str"], .keyword),
        .words(["true", "false", "self", "Self", "None", "Some", "Ok", "Err"], .constant),
        .match(#"\b(?:0x[\da-fA-F_]+|0b[01_]+|0o[0-7_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)(?:[iuf](?:8|16|32|64|128|size))?\b"#,
               .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// PHP (the code parts; the HTML around them stays plain).
    public static let php = Grammar(name: "PHP", rules: [
        .match(#"<\?(?:php|=)?|\?>"#, .keyword),
        .match("(?://|#(?!\\[)).*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""#, #"""#, .string, rules: [
            .match(#"\\."#, .stringEscape),
            .match(#"\$[A-Za-z_]\w*"#, .variable),
        ]),
        .span("'", "'", .string, rules: [.match(#"\\[\\']"#, .stringEscape)]),
        .match(#"\$[A-Za-z_]\w*"#, .variable),
        .match(#"(?i)\b(?:abstract|and|array|as|break|callable|case|catch|class|clone|const|continue|declare|"#
               + #"default|do|echo|else|elseif|empty|enum|extends|final|finally|fn|for|foreach|function|global|"#
               + #"if|implements|include|include_once|instanceof|insteadof|interface|isset|list|match|namespace|"#
               + #"new|or|print|private|protected|public|readonly|require|require_once|return|static|switch|"#
               + #"throw|trait|try|unset|use|var|while|xor|yield)\b"#, .keyword),
        .match(#"(?i)\b(?:true|false|null)\b"#, .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// Ruby.
    public static let ruby = Grammar(name: "Ruby", rules: [
        .span(#"^=begin\b"#, #"^=end\b.*$"#, .comment),
        .match(#"#(?!\{).*$"#, .comment),
        .span(#"""#, #"""#, .string, rules: [
            .match(#"#\{[^}\n]*\}"#, .variable),                                  // #{interpolation}
            .match(#"\\."#, .stringEscape),
        ]),
        .span("'", "'", .string, rules: [.match(#"\\[\\']"#, .stringEscape)]),
        .match(#"(?<![:\w]):[A-Za-z_]\w*[?!]?"#, .constant),                      // :symbols
        .match(#"@@?[A-Za-z_]\w*|\$[A-Za-z_]\w*"#, .variable),                     // @ivar, @@cvar, $global
        .words(["BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
                "else", "elsif", "end", "ensure", "for", "if", "in", "module", "next", "not", "or", "redo",
                "rescue", "retry", "return", "super", "then", "undef", "unless", "until", "when", "while",
                "yield", "require", "require_relative", "attr_reader", "attr_writer", "attr_accessor",
                "private", "protected", "public", "raise"], .keyword),
        .words(["true", "false", "nil", "self"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"(?<=\bdef\s)(?:self\.)?[A-Za-z_]\w*[?!=]?"#, .function),
    ])
}
