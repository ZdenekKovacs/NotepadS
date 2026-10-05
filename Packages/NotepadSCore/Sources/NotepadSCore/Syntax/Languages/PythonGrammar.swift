extension Grammar {
    /// Python 3.
    public static let python = Grammar(name: "Python", rules: [
        .match("#.*$", .comment),
        // Triple-quoted strings span lines; listed before single quotes so they win the tie.
        // Prefixed strings (r"", b"", f"", rb"" …) first: their match starts earlier, at the letter.
        .span(#"\b[rRbBuUfF]{1,2}""""#, #"""""#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"\b[rRbBuUfF]{1,2}'''"#, "'''", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"\b[rRbBuUfF]{1,2}""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"\b[rRbBuUfF]{1,2}'"#, "'|$", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"""""#, #"""""#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'''", "'''", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'", "'|$", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"^\s*@[\w.]+"#, .function),                       // decorators
        .match(#"(?<=\bdef\s)[A-Za-z_]\w*"#, .function),
        .match(#"(?<=\bclass\s)[A-Za-z_]\w*"#, .function),
        .words(["and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def",
                "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import",
                "in", "is", "lambda", "match", "nonlocal", "not", "or", "pass", "raise", "return",
                "try", "while", "with", "yield"], .keyword),
        .words(["True", "False", "None", "self"], .constant),
        .match(#"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?j?)\b"#,
               .number),
    ])
}
