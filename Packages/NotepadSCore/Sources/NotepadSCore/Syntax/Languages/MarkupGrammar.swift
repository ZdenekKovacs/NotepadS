extension Grammar {
    /// HTML. Tag names and the punctuation of a tag are shown as keywords, attribute names as
    /// properties and attribute values as strings. Script and style contents stay plain.
    public static let html = Grammar(name: "HTML", rules: [
        .span("<!--", "-->", .comment),
        .match(#"<![Dd][Oo][Cc][Tt][Yy][Pp][Ee][^>]*>"#, .keyword),
    ] + Grammar.markupRules)

    /// XML, including property lists and SVG.
    public static let xml = Grammar(name: "XML", rules: [
        .span("<!--", "-->", .comment),
        .span(#"<!\[CDATA\["#, #"\]\]>"#, .code),
        .span(#"<\?"#, #"\?>"#, .keyword, rules: Grammar.attributeRules),   // <?xml version="1.0"?>
        .match(#"<![A-Z]+[^>]*>"#, .keyword),                                 // <!DOCTYPE …>, <!ELEMENT …>
    ] + Grammar.markupRules)

    /// A tag may span lines (long attribute lists), so it is a span from `<name` to `>`.
    private static let markupRules: [Rule] = [
        .span(#"</?[A-Za-z_][\w:.-]*"#, "/?>", .keyword, rules: Grammar.attributeRules),
        .match(#"&(?:#\d+|#[xX][\da-fA-F]+|\w+);"#, .constant),                // &amp; &#233;
    ]

    private static let attributeRules: [Rule] = [
        .match(#"[\w:.-]+(?=\s*=)"#, .property),
        .match(#""[^"]*"|'[^']*'"#, .string),
    ]
}
