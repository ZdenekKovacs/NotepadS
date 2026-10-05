extension Grammar {
    /// Bourne-style shells: sh, bash, zsh.
    public static let shell = Grammar(name: "Shell", rules: [
        // `#` starts a comment only at the start of a word (`a#b` and `$#` are not comments).
        .match(#"(?:^|(?<=\s))#.*$"#, .comment),
        // Double-quoted strings may span lines and expand variables.
        .span(#"""#, #"""#, .string, rules: [
            .match(#"\\."#, .stringEscape),
            .match(Grammar.shellVariable, .variable),
        ]),
        // Single-quoted strings are literal: no escapes, no variables.
        .span("'", "'", .string),
        .match(Grammar.shellVariable, .variable),
        .words(["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case",
                "esac", "in", "function", "select", "time", "return", "break", "continue", "local",
                "export", "readonly", "declare", "unset", "shift", "source", "exit"], .keyword),
        .words(["true", "false"], .constant),
        .match(#"\b\d+\b"#, .number),
    ])

    /// `$NAME`, `${NAME…}`, and special parameters such as `$1`, `$@`, `$?`.
    private static let shellVariable = #"\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[0-9@#?$!*-]"#
}
