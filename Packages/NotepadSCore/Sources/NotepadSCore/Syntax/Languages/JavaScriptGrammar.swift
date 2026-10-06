extension Grammar {
    /// JavaScript (ECMAScript 2024), including JSX files.
    public static let javaScript = Grammar(name: "JavaScript",
                                           rules: Grammar.javaScriptRules(extraKeywords: []))

    /// TypeScript: JavaScript plus type-level keywords and built-in type names.
    public static let typeScript = Grammar(name: "TypeScript", rules: Grammar.javaScriptRules(extraKeywords: [
        "interface", "type", "enum", "implements", "declare", "namespace", "module", "readonly",
        "private", "protected", "public", "abstract", "keyof", "infer", "is", "asserts", "satisfies",
        "any", "unknown", "never", "string", "number", "boolean", "symbol", "bigint", "object",
    ]))

    private static func javaScriptRules(extraKeywords: [String]) -> [Rule] {
        [
            .match("//.*$", .comment),
            .span(#"/\*"#, #"\*/"#, .comment),
            .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
            .span("'", "'|$", .string, rules: [.match(#"\\."#, .stringEscape)]),
            // Template literals span lines; `${…}` placeholders are shown as variables.
            .span("`", "`", .string, rules: [
                .match(#"\\."#, .stringEscape),
                .match(#"\$\{[^}]*\}"#, .variable),
            ]),
            .words(["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
                    "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
                    "instanceof", "let", "new", "of", "return", "static", "super", "switch", "this", "throw",
                    "try", "typeof", "var", "void", "while", "with", "yield", "async", "await", "get", "set",
                    "from", "as"] + extraKeywords, .keyword),
            .words(["true", "false", "null", "undefined", "NaN", "Infinity"], .constant),
            .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?n?)\b"#,
                   .number),
            // A name followed by "(" is a call or a declaration. Keywords like `if (` are listed
            // first and win the tie.
            .match(#"\b[A-Za-z_$][\w$]*(?=\s*\()"#, .function),
        ]
    }
}
