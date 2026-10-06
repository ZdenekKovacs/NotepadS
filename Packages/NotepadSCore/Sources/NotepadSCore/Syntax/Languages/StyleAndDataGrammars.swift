extension Grammar {
    /// CSS, also good enough for SCSS and Less.
    public static let css = Grammar(name: "CSS", rules: [
        .span(#"/\*"#, #"\*/"#, .comment),
        .match(#"(?<![:\w])//.*$"#, .comment),                                   // SCSS/Less line comments
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'", "'|$", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"@[\w-]+"#, .keyword),                                           // @media, @import
        .match(#"!important\b"#, .keyword),
        // A property: a name before ":" in a declaration that ends with ";" on the same line,
        // so selectors like "a:hover {" aren't taken for properties.
        .match(#"(?<![\w-])-?[a-zA-Z][\w-]*(?=\s*:[^;{}]*;)"#, .property),
        .match(#"\$[\w-]+|--[\w-]+"#, .variable),                                // SCSS and custom properties
        .match(#"#[0-9a-fA-F]{3,8}\b"#, .number),                                // colors
        .match(#"(?<![\w-])-?(?:\d+\.?\d*|\.\d+)(?:px|em|rem|%|vh|vw|vmin|vmax|ch|ex|pt|cm|mm|in|s|ms|deg|rad|turn|fr|dpi|dppx)?\b"#,
               .number),
        .match(#"[\w-]+(?=\()"#, .function),                                     // rgb(), calc(), var()
    ])

    /// SQL (ANSI plus common PostgreSQL, MySQL and SQLite words). Keywords in any case.
    public static let sql = Grammar(name: "SQL", rules: [
        .match("--.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span("'", "'(?!')", .string, rules: [.match("''", .stringEscape)]),
        .match(#""[^"\n]*"|`[^`\n]*`"#, .variable),                              // quoted identifiers
        .match(#"(?i)\b(?:select|from|where|and|or|not|insert|into|values|update|set|delete|create|table|view|index|"#
               + #"drop|alter|add|column|primary|key|foreign|references|unique|check|default|constraint|join|inner|"#
               + #"left|right|full|outer|cross|on|using|group|by|order|asc|desc|having|limit|offset|union|all|"#
               + #"distinct|as|in|exists|between|like|ilike|is|case|when|then|else|end|with|recursive|returning|"#
               + #"begin|commit|rollback|transaction|grant|revoke|if|replace|cascade|trigger|function|procedure|"#
               + #"declare|return|returns|language|int|integer|bigint|smallint|text|varchar|char|boolean|bool|"#
               + #"date|time|timestamp|numeric|decimal|real|float|double|serial|blob|json|jsonb|uuid)\b"#, .keyword),
        .match(#"(?i)\b(?:null|true|false)\b"#, .constant),
        .match(#"\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// TOML.
    public static let toml = Grammar(name: "TOML", rules: [
        .match("#.*$", .comment),
        .match(#"^\s*\[\[?[^\]\n]*\]\]?"#, .keyword),                           // [table], [[array]]
        .match(#"^\s*[\w."'-]+(?=\s*=)"#, .property),
        .span(#"""""#, #"""""#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'''", "'''", .string),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'", "'|$", .string),
        .words(["true", "false"], .constant),
        .match(#"\b\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)?\b"#, .number),
        .match(#"(?<![\w.])[+-]?(?:0x[\da-fA-F_]+|0o[0-7_]+|0b[01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?|inf|nan)\b"#,
               .number),
    ])

    /// INI and similar configuration files (.cfg, .conf, .properties, .editorconfig, .gitconfig).
    public static let ini = Grammar(name: "INI", rules: [
        .match(#"^\s*[;#].*$"#, .comment),
        .match(#"^\s*\[[^\]\n]*\]"#, .keyword),                                  // [section]
        .match(#"^\s*[^=:\s;#\[][^=:]*?(?=\s*[=:])"#, .property),
        .match(#""[^"\n]*"|'[^'\n]*'"#, .string),
        .match(#"(?i)(?<==|:|\s)(?:true|false|yes|no|on|off)\b"#, .constant),
        .match(#"(?<![\w.])-?\d+(?:\.\d+)?\b"#, .number),
    ])

    /// Unified diffs and patches: added lines green, removed lines red.
    public static let diff = Grammar(name: "Diff", rules: [
        .match(#"^(?:diff|index|similarity|rename|new file|deleted file|old mode|new mode) .*$"#, .keyword),
        .match(#"^(?:\+\+\+|---)(?: .*)?$"#, .keyword),
        .match(#"^@@.*?@@"#, .function),
        .match(#"^\+.*$"#, .inserted),
        .match(#"^-.*$"#, .deleted),
        .match(#"^\\.*$"#, .comment),                                            // "\ No newline at end of file"
    ])
}
