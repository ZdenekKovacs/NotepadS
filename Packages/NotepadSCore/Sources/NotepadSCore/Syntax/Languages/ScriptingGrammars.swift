extension Grammar {
    /// Lua. Long brackets (`[[…]]`, `--[[…]]`) are matched with any level of `=` signs;
    /// `[==[` closed by `]]` is a rare mismatch this accepts.
    public static let lua = Grammar(name: "Lua", rules: [
        .span(#"--\[=*\["#, #"\]=*\]"#, .comment),
        .match("--.*$", .comment),
        .span(#"\[=*\["#, #"\]=*\]"#, .string),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'", "'|$", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .words(["and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if", "in", "local",
                "not", "or", "repeat", "return", "then", "until", "while"], .keyword),
        .words(["true", "false", "nil", "self"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F]+(?:\.[\da-fA-F]*)?(?:[pP][+-]?\d+)?|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*[({"'])"#, .function),
    ])

    /// Perl 5. POD blocks and everything after `__END__` are shown as comments.
    public static let perl = Grammar(name: "Perl", rules: [
        .span(#"^=[a-zA-Z]"#, #"^=cut\b.*$"#, .comment),                        // POD documentation
        .span(#"^__(?:END|DATA)__\b"#, "(?!)", .comment),                       // the rest of the file is data
        .match(#"(?<![$\\])#.*$"#, .comment),
        .span(#"""#, #"""#, .string, rules: [
            .match(#"\\."#, .stringEscape),
            .match(#"[$@][A-Za-z_][\w:]*|\$\{[^}\n]*\}"#, .variable),
        ]),
        .span("'", "'", .string, rules: [.match(#"\\[\\']"#, .stringEscape)]),
        .match(#"[$@%][A-Za-z_][\w:]*|\$\{[^}\n]*\}|\$[\d&`'+!@/\\,;.0_]|\$#\w+"#, .variable),
        .words(["BEGIN", "END", "and", "cmp", "continue", "defined", "delete", "die", "do", "each", "else",
                "elsif", "eq", "eval", "exists", "for", "foreach", "ge", "gt", "if", "keys", "last", "le",
                "local", "lt", "my", "ne", "next", "no", "not", "or", "our", "package", "print", "printf",
                "redo", "ref", "require", "return", "say", "scalar", "shift", "sub", "undef", "unless", "until",
                "use", "values", "wantarray", "warn", "while", "xor"], .keyword),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"(?<=\bsub\s)\w+|\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// R.
    public static let r = Grammar(name: "R", rules: [
        .match("#.*$", .comment),
        .span(#"""#, #"""#, .string, rules: [.match(#"\\."#, .stringEscape)]),   // strings may span lines
        .span("'", "'", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match("`[^`\n]*`", .variable),                                         // `non-syntactic names`
        .words(["break", "else", "for", "function", "if", "in", "next", "repeat", "return", "switch",
                "while", "library", "require"], .keyword),
        .words(["TRUE", "FALSE", "NULL", "NA", "NA_integer_", "NA_real_", "NA_character_", "Inf", "NaN"],
               .constant),
        .match(#"<<?-|->>?|%[^%\n]*%|\|>"#, .operator),
        .match(#"\b(?:0[xX][\da-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)[Li]?\b"#, .number),
        .match(#"[A-Za-z.][\w.]*(?=\s*\()"#, .function),
    ])

    /// Tcl/Tk.
    public static let tcl = Grammar(name: "Tcl", rules: [
        .match(#"(?:^\s*|;\s*)#.*$"#, .comment),                                // comments only where a command starts
        .span(#"""#, #""|$"#, .string, rules: [
            .match(#"\\."#, .stringEscape),
            .match(#"\$(?:\{[^}\n]*\}|[\w:]+)"#, .variable),
        ]),
        .match(#"\$(?:\{[^}\n]*\}|[\w:]+(?:\([^)\n]*\))?)"#, .variable),
        .match(#"(?<=\bproc\s)\S+"#, .function),
        .words(["after", "append", "array", "break", "catch", "cd", "close", "concat", "continue", "dict",
                "else", "elseif", "error", "eval", "exec", "exit", "expr", "file", "for", "foreach", "format",
                "gets", "global", "if", "incr", "info", "join", "lappend", "lassign", "lindex", "linsert",
                "list", "llength", "lmap", "lrange", "lreplace", "lsearch", "lset", "lsort", "namespace",
                "open", "package", "proc", "puts", "read", "regexp", "regsub", "rename", "return", "scan",
                "set", "source", "split", "string", "subst", "switch", "then", "throw", "trace", "try", "unset",
                "uplevel", "upvar", "variable", "vwait", "while"], .keyword),
        .match(#"(?<![\w-])-[a-z]+\b"#, .property),                               // options: -nocase
        .match(#"\b(?:0[xX][\da-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)\b"#, .number),
    ])

    /// CoffeeScript.
    public static let coffeeScript = Grammar(name: "CoffeeScript", rules: [
        .span("###", "###", .comment),
        .match("#.*$", .comment),
        .span(#"""""#, #"""""#, .string, rules: Grammar.coffeeStringRules),
        .span("'''", "'''", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"""#, #"""#, .string, rules: Grammar.coffeeStringRules),
        .span("'", "'", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match("`[^`\n]*`", .code),                                            // embedded JavaScript
        .match(#"@\w*"#, .variable),                                           // @property = this.property
        .words(["and", "await", "break", "by", "catch", "class", "continue", "default", "delete", "do", "else",
                "export", "extends", "finally", "for", "if", "import", "in", "instanceof", "is", "isnt", "loop",
                "new", "not", "of", "or", "own", "return", "super", "switch", "then", "throw", "try", "typeof",
                "unless", "until", "when", "while", "yield"], .keyword),
        .words(["true", "false", "yes", "no", "on", "off", "null", "undefined", "this", "NaN", "Infinity"],
               .constant),
        .match(#"\b(?:0[xX][\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[A-Za-z_$][\w$]*(?=\s*[:=]\s*(?:\([^)\n]*\)\s*)?[-=]>)"#, .function),   // name = (a) ->
    ])

    private static let coffeeStringRules: [Rule] = [
        .match(#"\\."#, .stringEscape),
        .match(#"#\{[^}\n]*\}"#, .variable),
    ]
}
