extension Grammar {
    /// YAML 1.2.
    public static let yaml = Grammar(name: "YAML", rules: [
        // `#` starts a comment only at the start of a line or after whitespace (`a#b` is text).
        .match(#"(?:^|(?<=\s))#.*$"#, .comment),
        .match(#"^(?:---|\.\.\.)(?=\s|$)"#, .keyword),                         // document markers
        // List items; before keys, so "- port: 1" colors the dash, not "- port" as a key.
        .match(#"^\s*-(?=\s|$)"#, .keyword),
        // A key: plain or quoted text before a colon that is followed by a space or the line end.
        .match(#"(?<=^|\s|-\s|\{|,)[^\s#'"\[\]{},:&*!|>%@`][^#\n]*?(?=\s*:(?:\s|$))"#, .property),
        .match(#""(?:[^"\\]|\\.)*"(?=\s*:(?:\s|$))|'(?:[^']|'')*'(?=\s*:(?:\s|$))"#, .property),
        // Double-quoted strings may span lines and have escapes; single-quoted ones double their quote.
        .span(#"""#, #"""#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'", "'(?!')", .string, rules: [.match("''", .stringEscape)]),
        .match(#"[&*][\w.-]+"#, .variable),                                    // anchors and aliases
        .match(#"!!?[\w/.-]*"#, .keyword),                                     // tags
        .match(#"[|>][-+]?\d*(?=\s*(?:#.*)?$)"#, .keyword),                    // block scalars
        .match(#"(?<![\w.-])(?:true|false|null|yes|no|on|off|True|False|Null|TRUE|FALSE|NULL|~)(?![\w.-])"#, .constant),
        .match(#"(?<![\w.-])[-+]?(?:0x[0-9a-fA-F]+|\d[\d_]*(?:\.\d*)?(?:[eE][-+]?\d+)?|\.inf|\.nan)(?![\w.-])"#, .number),
    ])
}
