extension Grammar {
    /// MATLAB and GNU Octave.
    public static let matlab = Grammar(name: "MATLAB", rules: [
        .span(#"^\s*%\{\s*$"#, #"^\s*%\}\s*$"#, .comment),                      // %{ block comment %}
        .match(#"%.*$|\.\.\..*$"#, .comment),                                    // also text after ... (continuation)
        .span(#"""#, #""(?!")|$"#, .string, rules: [.match(#""""#, .stringEscape)]),
        // A quote right after a name, a number, `)`, `]`, `}`, `.` or another quote is the
        // transpose operator (a', x.'), not the start of a string.
        .span(#"(?<![\w)\]}.'])'"#, "'(?!')|$", .string, rules: [.match("''", .stringEscape)]),
        .words(["break", "case", "catch", "classdef", "continue", "else", "elseif", "end", "enumeration",
                "events", "for", "function", "global", "if", "methods", "otherwise", "parfor", "persistent",
                "properties", "return", "spmd", "switch", "try", "while"], .keyword),
        .words(["true", "false", "pi", "Inf", "inf", "NaN", "nan", "eps"], .constant),
        .match(#"\b\d+(?:\.\d*)?(?:[eE][+-]?\d+)?[ij]?\b|\.\d+(?:[eE][+-]?\d+)?\b"#, .number),
        // function name(…), function y = name(…), function [a, b] = name(…)
        .match(#"(?<=\bfunction\s{1,3})[A-Za-z_]\w*(?=\s*(?:\(|$))|(?<=\bfunction\s{1,3}(?:\[[^\]\n]{0,80}\]|[A-Za-z_]\w{0,40})\s{0,3}=\s{0,3})[A-Za-z_]\w*"#,
               .function),
    ])

    /// Fortran, free form (.f90 and later) and fixed form (.f, .for, .f77: a `C`, `c` or `*`
    /// in column 1 starts a comment). Keywords in any case.
    public static let fortran = Grammar(name: "Fortran", rules: [
        .match("!.*$", .comment),
        .match(#"^[Cc*](?:\s.*)?$"#, .comment),                                  // fixed-form comment line
        .span(#"""#, #""(?!")|$"#, .string, rules: [.match(#""""#, .stringEscape)]),
        .span("'", "'(?!')|$", .string, rules: [.match("''", .stringEscape)]),
        .match(#"(?i)\.(?:true|false)\."#, .constant),
        .match(#"(?i)\.(?:and|or|not|eqv|neqv|eq|ne|lt|le|gt|ge)\."#, .operator),
        .wordsIgnoringCase(["allocatable", "allocate", "associate", "block", "call", "case", "character",
                            "class", "close", "common", "complex", "contains", "continue", "cycle", "data",
                            "deallocate", "default", "dimension", "do", "double", "elemental", "else", "elseif",
                            "elsewhere", "end", "enddo", "endif", "entry", "equivalence", "exit", "external",
                            "forall", "format", "function", "go", "goto", "if", "implicit", "import", "in",
                            "include", "inout", "integer", "intent", "interface", "intrinsic", "kind", "len",
                            "logical", "module", "namelist", "none", "nullify", "only", "open", "optional",
                            "out", "parameter", "pointer", "precision", "print", "private", "procedure",
                            "program", "protected", "public", "pure", "read", "real", "recursive", "result",
                            "return", "rewind", "save", "select", "sequence", "stop", "subroutine", "target",
                            "then", "to", "type", "use", "value", "where", "while", "write"], .keyword),
        .match(#"(?i)\b\d+(?:\.\d*)?(?:[ed][+-]?\d+)?(?:_\w+)?\b|\.\d+(?:[ed][+-]?\d+)?\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// LaTeX and TeX.
    public static let latex = Grammar(name: "LaTeX", rules: [
        .match("%.*$", .comment),
        .match(#"\\(?:part|chapter|section|subsection|subsubsection|paragraph|subparagraph)\*?(?:\[[^\]\n]*\])?\{[^}\n]*\}"#,
               .heading),
        .match(#"\\(?:begin|end)\{[^}\n]*\}"#, .function),
        .span(#"\$\$|\\\["#, #"\$\$|\\\]"#, .code),                              // display math
        .span(#"\$"#, #"\$"#, .code, rules: [.match(#"\\."#, .code)]),           // inline math
        .match(#"\\(?:[A-Za-z@]+|.)"#, .keyword),                                 // commands, \%, \\
        .match(#"(?<=\\textbf\{)[^}\n]*|(?<=\\emph\{)[^}\n]*|(?<=\\textit\{)[^}\n]*"#, .emphasis),
        .match(#"[{}\[\]&]"#, .operator),
    ])

    /// PostScript (and EPS).
    public static let postScript = Grammar(name: "PostScript", rules: [
        .match(#"^%[%!].*$"#, .keyword),                                          // %!PS, %%BoundingBox: DSC comments
        .match("%.*$", .comment),
        .span(#"\("#, #"\)"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"<~[^~]*~>|<[\da-fA-F\s]*>"#, .string),                            // ASCII85 and hex strings
        .match(#"/[^\s/(){}<>\[\]%]+"#, .constant),                                // /names
        .words(["abs", "add", "aload", "arc", "arcn", "array", "begin", "bind", "clip", "closepath", "concat",
                "copy", "curveto", "currentpoint", "def", "dict", "div", "dup", "end", "eq", "exch", "exec",
                "exit", "fill", "findfont", "for", "forall", "ge", "get", "grestore", "gsave", "gt", "if",
                "ifelse", "index", "le", "length", "lineto", "load", "loop", "lt", "makefont", "moveto", "mul",
                "ne", "neg", "newpath", "not", "pop", "put", "rcurveto", "repeat", "rlineto", "rmoveto", "roll",
                "rotate", "scale", "scalefont", "setdash", "setfont", "setgray", "setlinewidth", "setrgbcolor",
                "show", "showpage", "stringwidth", "stroke", "sub", "translate", "true", "false", "null"],
               .keyword),
        .match(#"(?<![\w.])[+-]?(?:\d+#[\da-zA-Z]+|\d*\.?\d+(?:[eE][+-]?\d+)?)(?![\w.])"#, .number),
    ])

    /// CMake (CMakeLists.txt, *.cmake).
    public static let cmake = Grammar(name: "CMake", rules: [
        .span(#"#\[=*\["#, #"\]=*\]"#, .comment),
        .match("#.*$", .comment),
        .span(#"\[=*\["#, #"\]=*\]"#, .string),                                    // bracket arguments
        .span(#"""#, #"""#, .string, rules: [
            .match(#"\\."#, .stringEscape),
            .match(#"\$(?:ENV|CACHE)?\{[^}\n]*\}"#, .variable),
        ]),
        .match(#"\$(?:ENV|CACHE)?\{[^}\n]*\}|\$<[^>\n]*>"#, .variable),            // ${VAR}, $<generator>
        .match(#"(?i)\b(?:if|elseif|else|endif|foreach|endforeach|while|endwhile|function|endfunction|macro|endmacro|return|break|continue|block|endblock)(?=\s*\()"#,
               .keyword),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),                             // commands
        .match(#"\b[A-Z][A-Z0-9_]{1,}\b"#, .constant),                              // PUBLIC, REQUIRED, ON, VERSION
        .match(#"\b\d+(?:\.\d+)*\b"#, .number),
    ])
}
