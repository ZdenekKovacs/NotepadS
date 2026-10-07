extension Grammar {
    /// Kotlin.
    public static let kotlin = Grammar(name: "Kotlin", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""""#, #"""""#, .string, rules: [Grammar.dollarTemplate]),     // raw strings span lines
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),
        .match(#"@[\w:]+"#, .function),                                         // annotations
        .words(["abstract", "actual", "annotation", "as", "break", "by", "catch", "class", "companion", "const",
                "constructor", "continue", "crossinline", "data", "do", "dynamic", "else", "enum", "expect",
                "external", "final", "finally", "for", "fun", "get", "if", "import", "in", "infix", "init",
                "inline", "inner", "interface", "internal", "is", "lateinit", "noinline", "object", "open",
                "operator", "out", "override", "package", "private", "protected", "public", "reified", "return",
                "sealed", "set", "suspend", "tailrec", "throw", "try", "typealias", "val", "value", "var",
                "vararg", "when", "where", "while"], .keyword),
        .words(["true", "false", "null", "this", "super", "it"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[uUlLfF]*\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*(?:<[\w\s,<>?]*>)?\s*[({])"#, .function),
    ])

    /// Scala (2 and 3).
    public static let scala = Grammar(name: "Scala", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"\w*""""#, #""""(?!")"#, .string, rules: [Grammar.dollarTemplate]),
        .span(#"\w*""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .match(#"'(?:[^'\\\n]|\\.)'"#, .string),
        .match(#"@\w+"#, .function),
        .words(["abstract", "case", "catch", "class", "def", "do", "else", "enum", "export", "extends",
                "extension", "final", "finally", "for", "forSome", "given", "if", "implicit", "import", "lazy",
                "match", "new", "object", "override", "package", "private", "protected", "return", "sealed",
                "then", "throw", "trait", "try", "type", "using", "val", "var", "while", "with", "yield"],
               .keyword),
        .words(["true", "false", "null", "this", "super", "None", "Some", "Nil", "Unit"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[lLfFdD]?\b"#, .number),
        .match(#"(?<=\bdef\s)[A-Za-z_]\w*"#, .function),
        .match(#"\b[a-z_]\w*(?=\s*\()"#, .function),
    ])

    /// Groovy, including Gradle build scripts.
    public static let groovy = Grammar(name: "Groovy", rules: [
        .match(#"^#!.*$"#, .comment),
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""""#, #"""""#, .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .span("'''", "'''", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .span("'", "'|$", .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"@\w+"#, .function),
        .words(["abstract", "as", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
                "const", "continue", "def", "default", "do", "double", "else", "enum", "extends", "final",
                "finally", "float", "for", "goto", "if", "implements", "import", "in", "instanceof", "int",
                "interface", "long", "native", "new", "package", "private", "protected", "public", "return",
                "short", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws",
                "trait", "transient", "try", "var", "void", "volatile", "while"], .keyword),
        .words(["true", "false", "null", "it"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[lLfFdDgG]?\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*[({])"#, .function),
    ])

    /// Dart.
    public static let dart = Grammar(name: "Dart", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"r""""#, #""""#, .string),
        .span("r'''", "'''", .string),
        .span(#"""""#, #"""""#, .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .span("'''", "'''", .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .match(#"r"[^"\n]*"|r'[^'\n]*'"#, .string),                              // raw strings
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .span("'", "'|$", .string, rules: [.match(#"\\."#, .stringEscape), Grammar.dollarTemplate]),
        .match(#"@\w+"#, .function),
        .words(["abstract", "as", "assert", "async", "await", "base", "break", "case", "catch", "class",
                "const", "continue", "covariant", "default", "deferred", "do", "dynamic", "else", "enum",
                "export", "extends", "extension", "external", "factory", "final", "finally", "for", "Function",
                "get", "hide", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin",
                "new", "on", "operator", "part", "required", "rethrow", "return", "sealed", "set", "show",
                "static", "super", "switch", "sync", "throw", "try", "typedef", "var", "void", "when", "while",
                "with", "yield", "bool", "double", "int", "num", "String", "List", "Map", "Set", "Object"],
               .keyword),
        .words(["true", "false", "null", "this"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*(?:<[\w\s,<>?]*>)?\s*\()"#, .function),
    ])

    /// `$name` and `${expression}` inside strings (Kotlin, Scala, Groovy, Dart).
    private static let dollarTemplate: Rule = .match(#"\$\{[^}\n]*\}|\$[A-Za-z_]\w*"#, .variable)

    /// Objective-C: C plus `@` keywords, `@"strings"` and the Objective-C types.
    public static let objectiveC = Grammar(name: "Objective-C", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .match(#"(?<=#import|#include)\s*<[^>\n]*>"#, .string),
        .match(#"^\s*#\s*\w+"#, .keyword),                                      // #import, #pragma
        .span(#"@?""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),
        .match(#"@\w+"#, .keyword),                                             // @interface, @property
        .words(["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
                "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "return",
                "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned",
                "void", "volatile", "while", "id", "instancetype", "BOOL", "SEL", "IMP", "Class", "atomic",
                "nonatomic", "strong", "weak", "copy", "assign", "retain", "readonly", "readwrite", "nullable",
                "nonnull", "__block", "__weak", "__strong", "in", "out", "inout", "bycopy", "byref", "oneway"],
               .keyword),
        .words(["YES", "NO", "nil", "Nil", "NULL", "self", "super", "true", "false"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)[uUlLfF]*\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()|\b[A-Za-z_]\w*:(?!:)"#, .function),     // calls and message parts
    ])
}
