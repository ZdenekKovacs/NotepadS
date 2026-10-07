extension Grammar {
    /// C#.
    public static let csharp = Grammar(name: "C#", rules: [
        .match("//.*$", .comment),
        .span(#"/\*"#, #"\*/"#, .comment),
        .span(#"\$*""""#, #""""#, .string),                                     // raw strings """…"""
        .span(#"\$?@\$?""#, #""(?!")"#, .string, rules: [                       // verbatim @"…", may span lines
            .match(#""""#, .stringEscape),
            .match(#"\{[^}\n]*\}"#, .variable),
        ]),
        .span(#"\$""#, #""|$"#, .string, rules: [                               // interpolated $"…{x}…"
            .match(#"\\."#, .stringEscape),
            .match(#"\{[^}\n]*\}"#, .variable),
        ]),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"'(?:[^'\\\n]|\\.)*'"#, .string),
        .match(#"^\s*#\s*\w+"#, .keyword),                                       // #region, #if
        .words(["abstract", "as", "async", "await", "bool", "break", "byte", "case", "catch", "char",
                "checked", "class", "const", "continue", "decimal", "default", "delegate", "do", "double",
                "dynamic", "else", "enum", "event", "explicit", "extern", "finally", "fixed", "float", "for",
                "foreach", "get", "goto", "if", "implicit", "in", "init", "int", "interface", "internal", "is",
                "lock", "long", "nameof", "namespace", "new", "nint", "nuint", "object", "operator", "out",
                "override", "params", "partial", "private", "protected", "public", "readonly", "record", "ref",
                "required", "return", "sbyte", "sealed", "set", "short", "sizeof", "stackalloc", "static",
                "string", "struct", "switch", "throw", "try", "typeof", "uint", "ulong", "unchecked", "unsafe",
                "ushort", "using", "var", "virtual", "void", "volatile", "when", "where", "while", "with",
                "yield"], .keyword),
        .words(["true", "false", "null", "this", "base", "value"], .constant),
        .match(#"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)(?:[uU][lL]?|[lL][uU]?|[fFdDmM])?\b"#,
               .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*(?:<[\w\s,<>]*>)?\s*\()"#, .function),
    ])

    /// Visual Basic .NET, VBScript and VBA (`.bas`). Keywords in any case.
    public static let visualBasic = Grammar(name: "Visual Basic", rules: [
        .match(#"(?i)(?:'|\bREM\b).*$"#, .comment),
        .span(#"""#, #""(?!")|$"#, .string, rules: [.match(#""""#, .stringEscape)]),
        .match(#"^\s*#\s*\w+"#, .keyword),                                       // #If, #Region
        .wordsIgnoringCase(["AddHandler", "AddressOf", "Alias", "And", "AndAlso", "As", "Boolean", "ByRef",
                            "Byte", "ByVal", "Call", "Case", "Catch", "CBool", "CByte", "CChar", "CDate",
                            "CDbl", "CDec", "Char", "CInt", "Class", "CLng", "CObj", "Const", "Continue",
                            "CShort", "CSng", "CStr", "CType", "Date", "Decimal", "Declare", "Default",
                            "Delegate", "Dim", "DirectCast", "Do", "Double", "Each", "Else", "ElseIf", "End",
                            "Enum", "Erase", "Error", "Event", "Exit", "Explicit", "Finally", "For", "Friend",
                            "Function", "Get", "GetType", "Global", "GoTo", "Handles", "If", "Implements",
                            "Imports", "In", "Inherits", "Integer", "Interface", "Is", "IsNot", "Let", "Lib",
                            "Like", "Long", "Loop", "Mod", "Module", "MustInherit", "MustOverride", "MyBase",
                            "MyClass", "Namespace", "New", "Next", "Not", "Object", "Of", "On", "Operator",
                            "Option", "Optional", "Or", "OrElse", "Overloads", "Overridable", "Overrides",
                            "ParamArray", "Partial", "Private", "Property", "Protected", "Public", "RaiseEvent",
                            "ReadOnly", "ReDim", "RemoveHandler", "Resume", "Return", "Select", "Set",
                            "Shadows", "Shared", "Short", "Single", "Static", "Step", "Stop", "String",
                            "Structure", "Sub", "SyncLock", "Then", "Throw", "To", "Try", "TryCast", "TypeOf",
                            "Until", "Using", "Variant", "Wend", "When", "While", "With", "WithEvents",
                            "WriteOnly", "Xor"], .keyword),
        .wordsIgnoringCase(["True", "False", "Nothing", "Me", "Null", "Empty"], .constant),
        .match(#"(?i)&H[\da-f]+&?|&O[0-7]+&?|\b\d+(?:\.\d+)?(?:E[+-]?\d+)?[%&@!#]?"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// PowerShell.
    public static let powerShell = Grammar(name: "PowerShell", rules: [
        .span("<#", "#>", .comment),
        .match("#.*$", .comment),
        .span(#"@"$"#, #"^"@"#, .string, rules: [                                // here-strings
            .match(#"`."#, .stringEscape),
            .match(#"\$(?:\{[^}\n]*\}|[\w:]+)"#, .variable),
        ]),
        .span(#"@'$"#, #"^'@"#, .string),
        .span(#"""#, #"""#, .string, rules: [
            .match(#"`."#, .stringEscape),
            .match(#"\$(?:\{[^}\n]*\}|\([^)\n]*\)|[\w:]+)"#, .variable),
        ]),
        .span("'", "'(?!')", .string, rules: [.match("''", .stringEscape)]),
        .match(#"(?i)\$(?:true|false|null)\b"#, .constant),
        .match(#"\$(?:\{[^}\n]*\}|[\w:?^$]+)"#, .variable),
        .wordsIgnoringCase(["begin", "break", "catch", "class", "continue", "data", "do", "dynamicparam", "else",
                            "elseif", "end", "enum", "exit", "filter", "finally", "for", "foreach", "function",
                            "hidden", "if", "in", "param", "process", "return", "static", "switch", "throw",
                            "trap", "try", "until", "using", "while"], .keyword),
        .match(#"(?i)-(?:[ci]?(?:eq|ne|gt|ge|lt|le|like|notlike|match|notmatch|contains|notcontains|in|notin|replace|split)|join|and|or|not|xor|is|isnot|as|band|bor|bxor|bnot|f)\b"#,
               .operator),
        .match(#"(?<=\s)-[A-Za-z]\w*"#, .property),                                 // parameters: -Path
        .match(#"\[[A-Za-z][\w.]*(?:\[\])?\]"#, .keyword),                         // [string], [int[]]
        .match(#"\b[A-Za-z]+-[A-Za-z]\w*"#, .function),                              // Get-ChildItem
        .match(#"\b(?:0x[\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)(?:[kKmMgGtTpP][bB])?\b"#, .number),
    ])

    /// Windows batch files (.bat, .cmd). Commands in any case.
    public static let batch = Grammar(name: "Batch", rules: [
        .match(#"(?i)^\s*@?(?:rem(?:\s.*)?|::.*)$"#, .comment),
        .match(#"^\s*:[^:\s]\S*"#, .function),                                   // :label
        .span(#"""#, #""|$"#, .string, rules: [
            .match(#"%%~?\w|%[\w~:=,.\-\s]*%|![\w.\-]+!"#, .variable),
        ]),
        .match(#"%%~?\w|%~?[\d*]|%[\w~:=,.\-]+%|![\w.\-]+!"#, .variable),
        .wordsIgnoringCase(["call", "cd", "chdir", "choice", "cls", "copy", "defined", "del", "dir", "do",
                            "echo", "else", "endlocal", "equ", "errorlevel", "exist", "exit", "for", "geq",
                            "goto", "gtr", "if", "in", "leq", "lss", "md", "mkdir", "move", "neq", "not", "nul",
                            "off", "on", "pause", "popd", "pushd", "rd", "ren", "rmdir", "set", "setlocal",
                            "shift", "start", "title", "type", "xcopy", "enabledelayedexpansion"], .keyword),
        .match(#"(?<!\w)/[A-Za-z?]\b"#, .property),                                // switches: /b /a
        .match(#"\b\d+\b"#, .number),
    ])

    /// Windows Registry files (.reg), as exported by Regedit.
    public static let registry = Grammar(name: "Windows Registry", rules: [
        .match(#"^(?:Windows Registry Editor Version [\d.]+|REGEDIT4)\s*$"#, .keyword),
        .match(";.*$", .comment),
        .match(#"^\s*\[[^\]\n]*\]"#, .heading),                                   // [HKEY_…\Key]
        .match(#"^\s*(?:"(?:[^"\\\n]|\\.)*"|@)(?=\s*=)"#, .property),              // "Name"= or @=
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .match(#"(?i)\b(?:dword|qword|hex(?:\([\da-f]+\))?)(?=:)"#, .keyword),
        .match(#"(?<=[:,])\s*[\da-fA-F]+\b"#, .number),
    ])

    /// AutoIt v3 scripts. Keywords in any case.
    public static let autoIt = Grammar(name: "AutoIt", rules: [
        .span(#"(?i)^\s*#c(?:s|omments-start)\b"#, #"(?i)^\s*#c(?:e|omments-end)\b.*$"#, .comment),
        .match(";.*$", .comment),
        .match(#"^\s*#[\w-]+"#, .keyword),                                       // #include, #RequireAdmin
        .span(#"""#, #""(?!")|$"#, .string, rules: [.match(#""""#, .stringEscape)]),
        .span("'", "'(?!')|$", .string, rules: [.match("''", .stringEscape)]),
        .match(#"\$\w+"#, .variable),
        .match(#"@\w+"#, .constant),                                             // macros: @ScriptDir
        .wordsIgnoringCase(["And", "ByRef", "Case", "Const", "ContinueCase", "ContinueLoop", "Default", "Dim",
                            "Do", "Else", "ElseIf", "EndFunc", "EndIf", "EndSelect", "EndSwitch", "EndWith",
                            "Enum", "Exit", "ExitLoop", "For", "Func", "Global", "If", "In", "Local", "Next",
                            "Not", "Or", "ReDim", "Return", "Select", "Static", "Step", "Switch", "Then", "To",
                            "Until", "Volatile", "WEnd", "While", "With"], .keyword),
        .wordsIgnoringCase(["True", "False", "Null"], .constant),
        .match(#"\b(?:0x[\da-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#, .number),
        .match(#"\b[A-Za-z_]\w*(?=\s*\()"#, .function),
    ])

    /// NSIS installer scripts (Nullsoft Scriptable Install System).
    public static let nsis = Grammar(name: "NSIS", rules: [
        .span(#"/\*"#, #"\*/"#, .comment),
        .match("[;#].*$", .comment),
        .match(#"^\s*![a-zA-Z]+"#, .keyword),                                    // !include, !define, !macro
        .span(#"""#, #""|$"#, .string, rules: Grammar.nsisStringRules),
        .span("'", "'|$", .string, rules: Grammar.nsisStringRules),
        .span("`", "`|$", .string, rules: Grammar.nsisStringRules),
        .match(#"\$\{[^}\n]*\}|\$\([^)\n]*\)|\$\w+"#, .variable),
        .match(#"(?<=^\s{0,40})[A-Za-z][\w.]*(?=\s|$)"#, .keyword),                // the command starting a line
        .match(#"(?<=\s)/[A-Za-z]+\b"#, .property),                                // /o, /REBOOTOK
        .match(#"\b(?:0x[\da-fA-F]+|\d+)\b"#, .number),
    ])

    private static let nsisStringRules: [Rule] = [
        .match(#"\$\\.|\$\$"#, .stringEscape),
        .match(#"\$\{[^}\n]*\}|\$\([^)\n]*\)|\$\w+"#, .variable),
    ]

    /// Inno Setup scripts (.iss): sections, `Name: value; Flags: …` parameters, {constants},
    /// and the Pascal keywords of the [Code] section.
    public static let innoSetup = Grammar(name: "Inno Setup", rules: [
        .match(#"^\s*;.*$|//.*$"#, .comment),
        .match(#"^\s*\[[^\]\n]+\]"#, .heading),                                   // [Setup], [Files]
        .match(#"^\s*#\s*\w+"#, .keyword),                                        // #define (preprocessor)
        .span(#"""#, #""(?!")|$"#, .string, rules: [
            .match(#""""#, .stringEscape),
            .match(#"\{[^}\n]*\}"#, .constant),
        ]),
        .span("'", "'(?!')|$", .string, rules: [.match("''", .stringEscape)]),
        .match(#"\{[#\w:,|\\ .]*\}"#, .constant),                                  // {app}, {#MyAppName}
        .match(#"^\s*\w+(?=\s*=)"#, .property),                                    // [Setup] Key=Value
        .match(#"\b[A-Za-z]\w*(?=\s*:\s)"#, .property),                            // Name: …; Source: …
        .wordsIgnoringCase(["and", "begin", "case", "const", "div", "do", "downto", "else", "end", "except",
                            "exit", "finally", "for", "function", "if", "mod", "not", "of", "or", "procedure",
                            "repeat", "then", "to", "try", "type", "until", "var", "while", "with"], .keyword),
        .wordsIgnoringCase(["True", "False", "nil", "yes", "no", "Result"], .constant),
        .match(#"\b\d+(?:\.\d+)*\b"#, .number),
    ])
}
