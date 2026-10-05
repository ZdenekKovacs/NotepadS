extension Grammar {
    /// JSON (RFC 8259). Object keys are colored differently from string values.
    public static let json = Grammar(name: "JSON", rules: [
        // A string followed by a colon is a key. Listed before strings so it wins the tie.
        .match(#""(?:[^"\\]|\\.)*"(?=\s*:)"#, .property),
        // JSON strings can't contain line breaks: an unterminated string ends with its line.
        .span(#"""#, #""|$"#, .string, rules: [
            .match(#"\\(?:u[0-9A-Fa-f]{4}|.)"#, .stringEscape),
        ]),
        .words(["true", "false", "null"], .constant),
        .match(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
    ])
}
