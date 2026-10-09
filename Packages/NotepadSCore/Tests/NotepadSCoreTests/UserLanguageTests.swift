import XCTest
@testable import NotepadSCore

final class UserLanguageTests: XCTestCase {

    private func sample() -> UserLanguage {
        var language = UserLanguage(name: "MyConf", fileExtensions: ["myconf", "cfg"])
        language.keywordGroups[0].words = ["if", "elseif", "end", "#define"]
        language.keywordGroups[1].words = ["true", "false"]
        language.lineComment = "#"
        language.blockCommentStart = "/*"
        language.blockCommentEnd = "*/"
        language.stringDelimiters = "\"'"
        return language
    }

    /// The scopes of `line` as "text:scope" pairs.
    private func tokens(_ line: String, _ language: UserLanguage) -> [String] {
        let text = line as NSString
        return language.grammar.tokenize(line: text, startingIn: .initial).tokens
            .map { "\(text.substring(with: $0.range)):\($0.scope.rawValue)" }
    }

    func testKeywordsCommentsStringsAndNumbers() {
        XCTAssertEqual(tokens(#"if x = "a\"b" end 42 # note"#, sample()),
                       ["if:keyword", #""a:string"#, #"\":stringEscape"#, #"b":string"#, "end:keyword", "42:number", "# note:comment"])
    }

    func testLongestKeywordWinsAndWholeWordsOnly() {
        XCTAssertEqual(tokens("elseif endif", sample()), ["elseif:keyword"], "\"endif\" is not \"end\"")
    }

    func testKeywordsStartingWithASymbol() {
        XCTAssertEqual(tokens("#define X", sample()), ["#define X:comment"], "the line comment wins at the same position")
        var language = sample()
        language.lineComment = "//"
        XCTAssertEqual(tokens("#define X", language), ["#define:keyword"])
    }

    func testIgnoringCase() {
        var language = sample()
        XCTAssertEqual(tokens("IF True", language), [])
        language.ignoresCase = true
        XCTAssertEqual(tokens("IF True", language), ["IF:keyword", "True:constant"])
    }

    func testStringEndsAtLineEndAndQuoteInCommentIsComment() {
        XCTAssertEqual(tokens(#"'open"#, sample()), ["'open:string"])
        XCTAssertEqual(tokens(#"# it's"#, sample()), ["# it's:comment"])
    }

    func testRegexCharactersAreLiteral() {
        var language = UserLanguage(name: "X")
        language.lineComment = ".*"
        language.keywordGroups[0].words = ["a+b", "(x)"]
        XCTAssertEqual(tokens("a+b (x) ab .* c", language), ["a+b:keyword", "(x):keyword", ".* c:comment"])
    }

    func testEmptyDefinitionHighlightsOnlyNumbersAndStrings() {
        XCTAssertEqual(tokens(#"word 3.5 "s""#, UserLanguage(name: "Empty")), ["3.5:number", #""s":string"#])
        var nothing = UserLanguage(name: "Nothing")
        nothing.stringDelimiters = ""
        nothing.highlightsNumbers = false
        XCTAssertEqual(tokens(#"word 3 "s""#, nothing), [])
    }

    func testBlockCommentAcrossLines() {
        let highlighter = Highlighter(grammar: sample().grammar, lineCount: 3)
        let text = "a /* one\ntwo */ end\nif" as NSString
        let lineIndex = LineIndex(text: text)
        let scopes = highlighter.tokens(forLines: 0..<3, in: text, lineIndex: lineIndex)
            .map { "\(text.substring(with: $0.range)):\($0.scope.rawValue)" }
        XCTAssertEqual(scopes, ["/* one:comment", "two */:comment", "end:keyword", "if:keyword"])
    }

    // MARK: - Fields from Settings

    func testWordsAndExtensionsFromTextFields() {
        XCTAssertEqual(UserLanguage.words(from: "if  then\r\nelse\tend\n"), ["if", "then", "else", "end"])
        XCTAssertEqual(UserLanguage.fileExtensions(from: " .CFG, *.mylog;cfg  txt2 "), ["cfg", "mylog", "txt2"])
    }

    // MARK: - Saving

    func testEncodeDecodeRoundTrip() throws {
        let languages = [sample(), UserLanguage(name: "Žluťoučký 😀")]
        XCTAssertEqual(try UserLanguage.decode(UserLanguage.encode(languages)), languages)
    }

    func testDecodingSomethingElseFails() {
        XCTAssertThrowsError(try UserLanguage.decode(Data("{\"a\": 1}".utf8))) {
            XCTAssertEqual($0 as? UserLanguageError, .unreadable)
        }
    }

    // MARK: - SyntaxLanguage

    func testUserLanguageWinsItsExtensions() {
        var language = sample()
        language.fileExtensions = ["cfg"]   // also built-in INI
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "app.CFG", firstLine: nil, userLanguages: [language]), .user(language))
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "app.cfg", firstLine: nil, userLanguages: []), .builtIn(.ini))
        XCTAssertEqual(SyntaxLanguage.detect(fileName: "run", firstLine: "#!/bin/sh", userLanguages: [language]), .builtIn(.shell))
    }

    func testIdentifiersAndUpdates() {
        var language = sample()
        let user = SyntaxLanguage.user(language)
        XCTAssertEqual(SyntaxLanguage(identifier: user.identifier, userLanguages: [language]), user)
        XCTAssertEqual(SyntaxLanguage(identifier: "python", userLanguages: []), .builtIn(.python))
        XCTAssertNil(SyntaxLanguage(identifier: user.identifier, userLanguages: []))
        language.name = "Renamed"
        XCTAssertEqual(user.updated(from: [language])?.displayName, "Renamed")
        XCTAssertNil(user.updated(from: []))
        XCTAssertTrue(user.includes(fileName: "x.MYCONF"))
        XCTAssertFalse(user.includes(fileName: "myconf"))
    }
}
