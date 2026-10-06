extension Grammar {
    /// Makefiles (GNU make).
    public static let makefile = Grammar(name: "Makefile", rules: [
        .match(#"(?:^|(?<=\s))#.*$"#, .comment),
        .match(#"^\s*-?(?:include|ifeq|ifneq|ifdef|ifndef|else|endif|define|endef|export|unexport|override|vpath)\b"#,
               .keyword),
        .match(#"^\s*[\w.-]+(?=\s*(?:\?|\+|::?|!)?=)"#, .property),              // VARIABLE = …
        .match(#"^[^\s:=#][^:=#\n]*(?=:(?!=))"#, .function),                      // target:
        .match(#"\$\([^)\n]*\)|\$\{[^}\n]*\}|\$[@<^+?*%|]"#, .variable),
        .span(#"""#, #""|$"#, .string, rules: [.match(#"\\."#, .stringEscape)]),
        .span("'", "'|$", .string),
    ])

    /// Dockerfiles and Containerfiles. Instructions in any case.
    public static let dockerfile = Grammar(name: "Dockerfile", rules: [
        .match(#"^\s*#.*$"#, .comment),
        .match(#"(?i)^\s*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|"#
               + #"ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b"#, .keyword),
        .match(#"(?i)\bAS\b"#, .keyword),
        .span(#"""#, #""|$"#, .string, rules: [
            .match(#"\\."#, .stringEscape),
            .match(#"\$\{[^}\n]*\}|\$[A-Za-z_]\w*"#, .variable),
        ]),
        .span("'", "'|$", .string),
        .match(#"\$\{[^}\n]*\}|\$[A-Za-z_]\w*"#, .variable),
        .match(#"--[\w-]+(?==)"#, .property),                                    // --from=, --chown=
    ])
}
