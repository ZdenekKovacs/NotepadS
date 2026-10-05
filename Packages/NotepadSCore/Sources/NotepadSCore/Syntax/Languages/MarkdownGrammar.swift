extension Grammar {
    /// Markdown (CommonMark plus the common GitHub extensions), colored line by line.
    public static let markdown = Grammar(name: "Markdown", rules: [
        // A fenced code block runs from an opening ``` or ~~~ line to the next closing fence.
        .span(#"^\s{0,3}(?:```|~~~).*$"#, #"^\s{0,3}(?:```|~~~)\s*$"#, .code),
        .span("<!--", "-->", .comment),
        .match(#"^\s{0,3}#{1,6}(?:\s.*)?$"#, .heading),
        .match("`[^`]+`", .code),
        .match(#"!?\[[^\]]*\]\([^)]*\)|<https?://[^>\s]+>"#, .link),
        .match(#"\*\*[^*]+\*\*|__[^_]+__"#, .strong),
        .match(#"(?<![*\w])\*[^*\s][^*]*\*(?![*\w])|(?<![_\w])_[^_\s][^_]*_(?![_\w])"#, .emphasis),
        .match(#"^\s*(?:[-*+]|\d+[.)])(?=\s)"#, .keyword),     // list markers
        .match(#"^\s{0,3}>"#, .keyword),                        // block quotes
    ])
}
