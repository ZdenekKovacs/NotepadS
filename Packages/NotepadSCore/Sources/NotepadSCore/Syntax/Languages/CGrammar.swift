extension Grammar {
    /// C (C17/C23).
    public static let c = Grammar(name: "C", rules: Grammar.cRules(extraKeywords: []))

    /// C++ (C++20/23): C plus the C++ keywords.
    public static let cpp = Grammar(name: "C++", rules: Grammar.cRules(extraKeywords: [
        "alignas", "alignof", "and", "asm", "catch", "class", "concept", "constexpr", "consteval",
        "constinit", "const_cast", "co_await", "co_return", "co_yield", "decltype", "delete",
        "dynamic_cast", "explicit", "export", "final", "friend", "mutable", "namespace", "new",
        "noexcept", "not", "operator", "or", "override", "private", "protected", "public",
        "reinterpret_cast", "requires", "static_assert", "static_cast", "template", "this", "throw",
        "try", "typeid", "typename", "using", "virtual",
    ]))

    private static func cRules(extraKeywords: [String]) -> [Rule] {
        [
            .match("//.*$", .comment),
            .span(#"/\*"#, #"\*/"#, .comment),
            // `#include <file>`: the file name is shown as a string.
            .match(#"(?<=#include)\s*<[^>\n]*>"#, .string),
            .match(#"^\s*#\s*\w+"#, .keyword),                                   // preprocessor
            .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
            .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),                              // character literals
            .words(["auto", "break", "case", "char", "const", "continue", "default", "do", "double",
                    "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
                    "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
                    "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "bool",
                    "_Bool"] + extraKeywords, .keyword),
            .words(["true", "false", "NULL", "nullptr"], .constant),
            .match(#"\b(?:0[xX][\da-fA-F']+|0[bB][01']+|\d[\d']*(?:\.[\d']*)?(?:[eE][+-]?\d+)?)[uUlLfFzZ]*\b"#,
                   .number),
            .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
        ]
    }
}
