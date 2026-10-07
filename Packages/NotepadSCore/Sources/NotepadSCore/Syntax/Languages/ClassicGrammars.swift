extension Grammar {
    /// Pascal, Delphi (Object Pascal) and Free Pascal. Keywords in any case.
    public static let pascal = Grammar(name: "Pascal/Delphi", rules: [
        .match("//.*$", .comment),
        .span(#"\{\$"#, #"\}"#, .keyword),                                        // {$IFDEF …} compiler directives
        .span(#"\{"#, #"\}"#, .comment),
        .span(#"\(\*"#, #"\*\)"#, .comment),
        .span("'", "'(?!')|$", .string, rules: [.match("''", .stringEscape)]),
        .match(#"#(?:\$[\da-fA-F]+|\d+)"#, .string),                               // character codes: #13#10
        .wordsIgnoringCase(["absolute", "abstract", "and", "array", "as", "asm", "begin", "boolean", "byte",
                            "cardinal", "case", "char", "class", "const", "constructor", "destructor", "div",
                            "do", "double", "downto", "dynamic", "else", "end", "except", "exports", "extended",
                            "file", "finalization", "finally", "for", "forward", "function", "goto", "if",
                            "implementation", "in", "inherited", "initialization", "inline", "int64", "integer",
                            "interface", "is", "label", "library", "longint", "mod", "not", "object", "of", "on",
                            "or", "out", "overload", "override", "packed", "private", "procedure", "program",
                            "property", "protected", "public", "published", "raise", "read", "real", "record",
                            "reintroduce", "repeat", "resourcestring", "set", "shl", "shr", "single", "strict",
                            "string", "then", "threadvar", "to", "try", "type", "unit", "until", "uses", "var",
                            "virtual", "while", "with", "word", "write", "xor"], .keyword),
        .wordsIgnoringCase(["true", "false", "nil", "self", "result"], .constant),
        .match(#"\$[\da-fA-F]+\b|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
        .match(#"(?i)(?<=\b(?:procedure|function|constructor|destructor)\s{1,4})[A-Za-z_][\w.]*"#, .function),
    ])

    /// COBOL, fixed format (a `*` or `/` in column 7 starts a comment line) and free format
    /// (`*>` comments). Keywords in any case; hyphens are part of words (END-IF, WORKING-STORAGE).
    public static let cobol = Grammar(name: "COBOL", rules: [
        .match(#"^.{6}[*/].*$"#, .comment),
        .match(#"\*>.*$"#, .comment),
        .span(#"""#, #""|$"#, .string),
        .span("'", "'|$", .string),
        .wordsIgnoringCase(["accept", "access", "add", "advancing", "after", "all", "and", "are", "ascending",
                            "assign", "at", "before", "binary", "by", "call", "cancel", "close", "comp", "comp-3",
                            "compute", "configuration", "continue", "copy", "data", "delete", "delimited",
                            "descending", "display", "divide", "division", "else", "end", "end-call",
                            "end-compute", "end-evaluate", "end-if", "end-perform", "end-read", "end-string",
                            "end-write", "environment", "equal", "evaluate", "exit", "extend", "fd", "file",
                            "file-control", "from", "function", "giving", "go", "goback", "greater", "id",
                            "identification", "if", "in", "indexed", "initialize", "input", "input-output",
                            "inspect", "into", "invalid", "is", "key", "less", "linkage", "local-storage", "mode",
                            "move", "multiply", "next", "not", "occurs", "of", "open", "or", "organization",
                            "other", "output", "perform", "pic", "picture", "procedure", "program", "program-id",
                            "read", "record", "redefines", "remainder", "replacing", "returning", "rewrite",
                            "rounded", "run", "section", "select", "sentence", "sequential", "set", "size",
                            "sort", "start", "stop", "string", "subtract", "tallying", "than", "then", "through",
                            "thru", "times", "to", "until", "unstring", "usage", "using", "value", "values",
                            "varying", "when", "with", "working-storage", "write"], .keyword, hyphenated: true),
        .wordsIgnoringCase(["zero", "zeros", "zeroes", "space", "spaces", "high-value", "high-values",
                            "low-value", "low-values", "quote", "quotes", "true", "false", "null"],
                           .constant, hyphenated: true),
        .match(#"(?<=^\s{0,40})\d{2}(?=\s)"#, .number),                            // level numbers: 01, 05, 77
        .match(#"(?<![\w-])[+-]?\d+(?:\.\d+)?(?![\w-])"#, .number),
    ])

    /// Ada. Keywords in any case.
    public static let ada = Grammar(name: "Ada", rules: [
        .match("--.*$", .comment),
        .span(#"""#, #""(?!")|$"#, .string, rules: [.match(#""""#, .stringEscape)]),
        .match(#"(?<=[\w)])'[A-Za-z_]\w*"#, .property),                            // attributes: X'First
        .match(#"'[^'\n]'"#, .string),                                             // characters: 'a'
        .wordsIgnoringCase(["abort", "abs", "abstract", "accept", "access", "aliased", "all", "and", "array",
                            "at", "begin", "body", "case", "constant", "declare", "delay", "delta", "digits",
                            "do", "else", "elsif", "end", "entry", "exception", "exit", "for", "function",
                            "generic", "goto", "if", "in", "interface", "is", "limited", "loop", "mod", "new",
                            "not", "null", "of", "or", "others", "out", "overriding", "package", "pragma",
                            "private", "procedure", "protected", "raise", "range", "record", "rem", "renames",
                            "requeue", "return", "reverse", "select", "separate", "some", "subtype",
                            "synchronized", "tagged", "task", "terminate", "then", "type", "until", "use",
                            "when", "while", "with", "xor"], .keyword),
        .wordsIgnoringCase(["True", "False"], .constant),
        .match(#"\b\d[\d_]*#[\da-fA-F_.]+#(?:[eE][+-]?\d+)?|\b\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?\b"#, .number),
        .match(#"(?i)(?<=\b(?:procedure|function)\s{1,4})[A-Za-z_][\w.]*"#, .function),
    ])

    /// Assembly: NASM/MASM (`;` comments) and GNU as (`#`, `//`, `/* */`), x86 and ARM registers.
    public static let assembly = Grammar(name: "Assembly", rules: [
        .match(";.*$", .comment),
        .match("//.*$", .comment),
        .match(#"^\s*#.*$"#, .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),
        .match(#"^\s*[\w.$@?]+:"#, .function),                                      // labels
        .match(#"(?<![\w.])\.[A-Za-z_]\w*"#, .keyword),                              // directives: .text, .globl
        .match(#"(?i)\b(?:section|segment|global|extern|bits|org|align|times|equ|db|dw|dd|dq|dt|resb|resw|resd|resq|proc|endp|macro|endm|include|byte|word|dword|qword|ptr|offset)\b"#,
               .keyword),
        .match(#"(?i)%?\b(?:[re]?[abcd]x|[abcd][lh]|[re]?(?:si|di|sp|bp|ip)|(?:si|di|sp|bp)l|r(?:[89]|1[0-5])[dwb]?|[xyz]mm\d{1,2}|[cdefgs]s|cr\d|dr\d|[xw](?:\d{1,2}|zr)|sp|lr|pc|fp)\b"#,
               .variable),                                                         // registers
        .match(#"(?<=^\s{0,40})[A-Za-z][\w.]*(?=\s|$)"#, .keyword),                 // the instruction on a line
        .match(#"(?i)[#$]?-?\b(?:0x[\da-f]+|0b[01]+|[\da-f]+h|\d+)\b"#, .number),
    ])

    /// D.
    public static let d = Grammar(name: "D", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"/\+"#, #"\+/"#, .comment),                                         // nesting comments (first +/ ends)
        .span(#"r""#, #"""#, .string),                                              // WYSIWYG strings
        .span("`", "`", .string),
        .span(#"""#, #""[cwd]?"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),
        .match(#"@\w+"#, .function),                                                // @safe, @nogc
        .match(#"^\s*#\s*line\b"#, .keyword),
        .words(["abstract", "alias", "align", "asm", "assert", "auto", "body", "bool", "break", "byte", "case",
                "cast", "catch", "char", "class", "const", "continue", "dchar", "debug", "default", "delegate",
                "deprecated", "do", "double", "else", "enum", "export", "extern", "final", "finally", "float",
                "for", "foreach", "foreach_reverse", "function", "goto", "if", "immutable", "import", "in",
                "inout", "int", "interface", "invariant", "is", "lazy", "long", "mixin", "module", "new",
                "nothrow", "out", "override", "package", "pragma", "private", "protected", "public", "pure",
                "real", "ref", "return", "scope", "shared", "short", "static", "struct", "switch",
                "synchronized", "template", "throw", "try", "typeid", "typeof", "ubyte", "uint", "ulong",
                "union", "unittest", "ushort", "version", "void", "wchar", "while", "with", "__gshared",
                "__traits"], .keyword),
        .words(["true", "false", "null", "this", "super"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]*)?(?:[eE][+-]?\d+)?)[uUlLfFi]*\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*(?:!\w+|!\([^)\n]*\))?\s*\()"#, .function),
    ])

    /// Verilog and SystemVerilog.
    public static let verilog = Grammar(name: "Verilog", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match("`[A-Za-z_]\\w*", .keyword),                                         // `define, `include, `timescale
        .match(#"\$[A-Za-z_]\w*"#, .function),                                      // $display, $finish
        .words(["always", "always_comb", "always_ff", "always_latch", "and", "assign", "automatic", "begin",
                "bit", "buf", "byte", "case", "casex", "casez", "class", "default", "defparam", "else", "end",
                "endcase", "endclass", "endfunction", "endgenerate", "endinterface", "endmodule", "endpackage",
                "endtask", "enum", "for", "forever", "fork", "function", "generate", "genvar", "if", "import",
                "initial", "inout", "input", "int", "integer", "interface", "join", "localparam", "logic",
                "module", "nand", "negedge", "nor", "not", "or", "output", "package", "parameter", "posedge",
                "real", "reg", "repeat", "return", "signed", "struct", "supply0", "supply1", "task", "time",
                "typedef", "unique", "unsigned", "virtual", "void", "wait", "while", "wire", "xor"], .keyword),
        .match(#"\b\d*'[sS]?[bBoOdDhH][\da-fA-FxXzZ_?]+|\b\d[\d_]*(?:\.\d+)?\b"#, .number),   // 8'hFF, 4'b10x1
    ])

    /// VHDL. Keywords in any case.
    public static let vhdl = Grammar(name: "VHDL", rules: [
        .match("--.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),                                          // VHDL-2008
        .span(#"""#, #""|$"#, .string),
        .match(#"(?<=[\w)])'[A-Za-z_]\w*"#, .property),                             // attributes: clk'event
        .match(#"'[01XZUWLH\-]'"#, .number),                                        // std_logic values: '1'
        .match(#"(?i)\b[bxo]"[\da-f_]*""#, .number),                                // x"FF", b"1010"
        .wordsIgnoringCase(["abs", "access", "after", "alias", "all", "and", "architecture", "array", "assert",
                            "attribute", "begin", "block", "body", "buffer", "bus", "case", "component",
                            "configuration", "constant", "downto", "else", "elsif", "end", "entity", "exit",
                            "file", "for", "function", "generate", "generic", "group", "if", "impure", "in",
                            "inout", "is", "label", "library", "linkage", "literal", "loop", "map", "mod",
                            "nand", "new", "next", "nor", "not", "null", "of", "on", "open", "or", "others",
                            "out", "package", "port", "postponed", "procedure", "process", "pure", "range",
                            "record", "register", "reject", "rem", "report", "return", "rol", "ror", "select",
                            "severity", "signal", "shared", "sla", "sll", "sra", "srl", "subtype", "then", "to",
                            "transport", "type", "unaffected", "units", "until", "use", "variable", "wait",
                            "when", "while", "with", "xnor", "xor"], .keyword),
        .wordsIgnoringCase(["std_logic", "std_logic_vector", "std_ulogic", "std_ulogic_vector", "signed",
                            "unsigned", "integer", "natural", "positive", "boolean", "bit", "bit_vector",
                            "string", "real", "time", "true", "false", "rising_edge", "falling_edge"], .constant),
        .match(#"\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .number),
    ])
}
