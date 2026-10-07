import Foundation

extension Grammar {
    /// Haskell. Nested `{- {- -} -}` comments end at the first `-}` (the tokenizer has no nesting).
    public static let haskell = Grammar(name: "Haskell", rules: [
        .span(#"\{-"#, #"-\}"#, .comment),                                       // also {-# PRAGMA #-}
        .match(#"--+(?![!#$%&*+./<=>?@\\^|~:]).*$"#, .comment),                   // but not the operator -->
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"(?<![\w'])'(?:[^'\\\n]|\\[^'\n]+)'"#, .string),                 // 'a', '\n' (not x')
        .words(["case", "class", "data", "default", "deriving", "do", "else", "family", "forall", "foreign",
                "hiding", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "mdo", "module",
                "newtype", "of", "proc", "qualified", "rec", "then", "type", "where"], .keyword),
        .match(#"\b[A-Z][\w']*"#, .constant),                                     // types and constructors
        .match(#"\b(?:0[xX][\da-fA-F]+|0[oO][0-7]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"^[a-z_][\w']*"#, .function),                                     // definitions start a line
    ])

    /// Erlang.
    public static let erlang = Grammar(name: "Erlang", rules: [
        .match("%.*$", .comment),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape), .match(#"~[\w.]*\w"#, .variable)]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .constant),                              // quoted atoms
        .match(#"\$\\?."#, .string),                                              // characters: $a, $\n
        .match(#"^-[a-z_]\w*"#, .keyword),                                         // -module, -export
        .match(#"\?[A-Za-z_]\w*"#, .constant),                                    // ?MODULE (macros)
        .words(["after", "and", "andalso", "band", "begin", "bnot", "bor", "bsl", "bsr", "bxor", "case",
                "catch", "cond", "div", "else", "end", "fun", "if", "let", "maybe", "not", "of", "or", "orelse",
                "receive", "rem", "try", "when", "xor"], .keyword),
        .words(["true", "false", "undefined", "ok", "error"], .constant),
        .match(#"\b[A-Z_][\w@]*"#, .variable),                                    // Variables start uppercase
        .match(#"\b(?:\d+#[\da-zA-Z]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[a-z][\w@]*(?=\s*\()"#, .function),
    ])

    /// Lisp dialects: Common Lisp, AutoLISP, Emacs Lisp, Scheme, Racket, Clojure.
    /// Special forms are colored only right after an opening parenthesis, as Lisp reads them.
    public static let lisp = Grammar(name: "Lisp", rules: [
        .span(#"#\|"#, #"\|#"#, .comment),
        .match(";.*$", .comment),
        .span(#"""#, #"""#, .string, rules: [.match(#"\\."#, .stringEscape)]),   // strings may span lines
        .match(#"#\\(?:[A-Za-z]{2,}\b|.)"#, .string),                             // characters: #\a, #\space
        .match(#"(?<=\(\s{0,4})(?:"# + Grammar.lispSpecialForms.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
               + #")(?=[\s()]|$)"#, .keyword),
        .match(#"(?<=\((?:defun|defmacro|defmethod|defgeneric|define|defn|defn-|defvar|defparameter)\s{1,4})[^\s()]+"#,
               .function),
        .match(#"(?<![\w-])(?:nil|t|T|NIL|true|false|#t|#f|#true|#false)(?![\w-])"#, .constant),
        .match(#"(?<![\w-]):[\w-]+"#, .constant),                                  // :keywords
        .match(#"'[\w*+!?<>=/-]+"#, .variable),                                    // 'quoted-symbols
        .match(#"(?<![\w-])[+-]?\d+(?:[./]\d+)?(?:[eE][+-]?\d+)?(?![\w-])"#, .number),
    ])

    private static let lispSpecialForms = [
        "defun", "defmacro", "defvar", "defparameter", "defconstant", "defstruct", "defclass", "defmethod",
        "defgeneric", "defpackage", "in-package", "lambda", "let", "let*", "flet", "labels", "if", "cond",
        "when", "unless", "case", "and", "or", "not", "progn", "prog1", "setq", "setf", "quote", "function",
        "loop", "do", "dolist", "dotimes", "return", "return-from", "block", "catch", "throw",
        "unwind-protect", "handler-case", "multiple-value-bind", "declare", "require", "provide", "define",
        "define-syntax", "let-values", "letrec", "begin", "set!", "else", "foreach", "repeat", "while",
        "vl-load-com", "defn", "defn-", "def", "fn", "ns", "recur",
    ]

    /// OCaml (and Caml). Nested comments end at the first `*)`.
    public static let ocaml = Grammar(name: "OCaml", rules: [
        .span(#"\(\*"#, #"\*\)"#, .comment),
        .span(#"""#, #"""#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"(?<![\w'])'(?:[^'\\\n]|\\[^'\n]+)'"#, .string),
        .words(["and", "as", "assert", "begin", "class", "constraint", "do", "done", "downto", "else", "end",
                "exception", "external", "for", "fun", "function", "functor", "if", "in", "include", "inherit",
                "initializer", "lazy", "let", "match", "method", "module", "mutable", "new", "nonrec", "object",
                "of", "open", "or", "private", "rec", "sig", "struct", "then", "to", "try", "type", "val",
                "virtual", "when", "while", "with"], .keyword),
        .words(["true", "false"], .constant),
        .match(#"\b[A-Z][\w']*"#, .constant),                                     // modules and constructors
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"(?<=\blet\s{1,3}|\blet\s{1,3}rec\s{1,3})[a-z_][\w']*"#, .function),   // let f, let rec f
    ])

    /// Smalltalk (Pharo, Squeak, GNU Smalltalk). Double quotes are comments, single quotes strings.
    public static let smalltalk = Grammar(name: "Smalltalk", rules: [
        .span(#"""#, #"""#, .comment),
        .span("'", "'(?!')", .string, rules: [.match("''", .stringEscape)]),
        .match(#"\$."#, .string),                                                  // characters: $a
        .match(#"#(?:[A-Za-z_][\w:]*|'[^'\n]*'|\()"#, .constant),                // #symbols, #( literal arrays
        .words(["self", "super", "nil", "true", "false", "thisContext"], .constant),
        .match(#"\b[A-Za-z_]\w*:(?!=)"#, .function),                              // keyword message parts: at:put:
        .match(#":[A-Za-z_]\w*"#, .variable),                                     // block parameters: [:x | …]
        .match(#"\b\d+r[\dA-Z]+|\b\d+(?:\.\d+)?(?:e-?\d+)?\b"#, .number),
        .match(#"\^"#, .keyword),                                                  // return
    ])
}
